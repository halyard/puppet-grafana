# @summary Configure Grafana instance
#
# @param hostname sets the hostname for grafana
# @param datadir sets where the data is persisted
# @param admin_user sets the username for the primary Grafana account
# @param admin_password sets the password for the primary Grafana account
# @param secret_key sets the AES key used for encrypting Grafana sessions
# @param client_id sets the Github OAuth client ID
# @param client_secret sets the Github OAuth client secret
# @param database_password sets the postgres password for grafana
# @param aws_access_key_id sets the AWS key to use for Route53 challenge
# @param aws_secret_access_key sets the AWS secret key to use for the Route53 challenge
# @param email sets the contact address for the certificate
# @param root_domain sets the publicly visible root domain for the site
# @param root_url sets the publicly visible root URL for the site
# @param container_ip sets the address of the Docker container
# @param postgres_ip sets the address of the postgres Docker container
# @param allow_anonymous determines whether unauthenticated users can view data
# @param anonymous_org sets the org for anonymous users
# @param anonymous_role sets the role for anonymous users
# @param viewers_can_edit controls whether viewers can use Explore and modify dashboard panels
# @param allowed_organizations sets the organization requirements for Github auth
# @param team_ids sets the team requirements for Github auth
# @param role_attribute_path sets how roles are mapped from Github metadata
# @param plugins sets the plugins to install
# @param extra_config sets extra grafana config flags to use
# @param backup_target sets the target repo for backups
# @param backup_data_watchdog sets the watchdog URL to confirm backups are working
# @param backup_provisioning_watchdog sets the watchdog URL to confirm backups are working
# @param backup_database_watchdog sets the watchdog URL to confirm backups are working
# @param backup_password sets the encryption key for backup snapshots
# @param backup_environment sets the env vars to use for backups
# @param backup_rclone sets the config for an rclone backend
# @param postgres_watchdog sets the watchdog URL for postgres dumps
class grafana (
  String $hostname,
  String $datadir,
  String $admin_user,
  String $admin_password,
  String $secret_key,
  String $client_id,
  String $client_secret,
  String $database_password,
  String $aws_access_key_id,
  String $aws_secret_access_key,
  String $email,
  Optional[String] $root_domain = undef,
  Optional[String] $root_url = undef,
  String $container_ip = '172.17.0.2',
  String $postgres_ip = '172.17.0.3',
  Boolean $allow_anonymous = false,
  String $anonymous_org = 'Main',
  String $anonymous_role = 'Viewer',
  Boolean $viewers_can_edit = false,
  Array[String] $allowed_organizations = [],
  Array[String] $team_ids = [],
  Optional[String] $role_attribute_path = undef,
  Array[String] $plugins = [],
  Array[String] $extra_config = [],
  Optional[String] $backup_target = undef,
  Optional[String] $backup_data_watchdog = undef,
  Optional[String] $backup_provisioning_watchdog = undef,
  Optional[String] $backup_database_watchdog = undef,
  Optional[String] $backup_password = undef,
  Optional[Hash[String, String]] $backup_environment = undef,
  Optional[String] $backup_rclone = undef,
  Optional[String] $postgres_watchdog = undef,
) {
  $hook_script =  "#!/usr/bin/env bash
cp \$LEGO_CERT_PATH ${datadir}/certs/cert
cp \$LEGO_CERT_KEY_PATH ${datadir}/certs/key
/usr/bin/systemctl restart container@grafana"

  file { [
      $datadir,
      "${datadir}/data",
      "${datadir}/provisioning",
      "${datadir}/certs",
      "${datadir}/backup",
      "${datadir}/postgres",
    ]:
      ensure => directory,
  }

  -> file { "${datadir}/grafana.ini":
    ensure  => file,
    content => template('grafana/grafana.ini.erb'),
    notify  => Service['container@grafana'],
  }

  -> acme::certificate { $hostname:
    hook_script           => $hook_script,
    aws_access_key_id     => $aws_access_key_id,
    aws_secret_access_key => $aws_secret_access_key,
    email                 => $email,
  }

  -> firewall { '100 dnat for grafana ui':
    chain  => 'DOCKER_EXPOSE',
    jump   => 'DNAT',
    proto  => 'tcp',
    dport  => 443,
    todest => "${container_ip}:3000",
    table  => 'nat',
  }

  -> docker::container { 'grafana':
    image => 'grafana/grafana-oss:latest',
    args  => [
      '--user root',
      "--ip ${container_ip}",
      "-v ${datadir}/data:/var/lib/grafana",
      "-v ${datadir}/provisioning:/etc/grafana/provisioning",
      "-v ${datadir}/grafana.ini:/etc/grafana/grafana.ini",
      "-v ${datadir}/certs:/mnt/certs",
      "-e GF_INSTALL_PLUGINS=${plugins.join(',')}",
      *$extra_config,
    ],
    cmd   => '',
  }

  firewall { '101 allow cross container from grafana to postgres':
    chain       => 'FORWARD',
    action      => 'accept',
    proto       => 'tcp',
    source      => $container_ip,
    destination => $postgres_ip,
    dport       => 5432,
  }

  docker::container { 'postgres':
    image   => 'postgres:17',
    args    => [
      "--ip ${postgres_ip}",
      "-v ${datadir}/postgres:/var/lib/postgresql/data",
      '-e POSTGRES_USER=grafana',
      "-e POSTGRES_PASSWORD=${database_password}",
      '-e POSTGRES_DB=grafana',
    ],
    cmd     => '-c ssl=on -c ssl_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem -c ssl_key_file=/etc/ssl/private/ssl-cert-snakeoil.key',
    require => File["${datadir}/postgres"],
  }

  file { '/usr/local/bin/grafana-backup.sh':
    ensure => file,
    source => 'puppet:///modules/grafana/grafana-backup.sh',
    mode   => '0755',
  }

  file { '/etc/systemd/system/grafana-backup.service':
    ensure  => file,
    content => template('grafana/grafana-backup.service.erb'),
    notify  => Service['grafana-backup.timer'],
  }

  file { '/etc/systemd/system/grafana-backup.timer':
    ensure => file,
    source => 'puppet:///modules/grafana/grafana-backup.timer',
    notify => Service['grafana-backup.timer'],
  }

  service { 'grafana-backup.timer':
    ensure => running,
    enable => true,
  }

  tidy { "${datadir}/backup weekly":
    path    => "${datadir}/backup",
    age     => '1d',
    recurse => true,
    matches => 'dump_??????{01,07,14,21,28}-??????.sql',
  }

  tidy { "${datadir}/backup all":
    path    => "${datadir}/backup",
    age     => '14d',
    recurse => true,
    matches => 'dump_*.sql',
  }

  if $backup_target != '' {
    backup::repo { 'grafana':
      source        => "${datadir}/data",
      target        => "${backup_target}/data",
      watchdog_url  => $backup_data_watchdog,
      password      => $backup_password,
      environment   => $backup_environment,
      rclone_config => $backup_rclone,
    }

    backup::repo { 'grafana-provisioning':
      source        => "${datadir}/provisioning",
      target        => "${backup_target}/provisioning",
      watchdog_url  => $backup_provisioning_watchdog,
      password      => $backup_password,
      environment   => $backup_environment,
      rclone_config => $backup_rclone,
    }

    backup::repo { 'grafana-database':
      source        => "${datadir}/backup",
      target        => "${backup_target}/database",
      watchdog_url  => $backup_database_watchdog,
      password      => $backup_password,
      environment   => $backup_environment,
      rclone_config => $backup_rclone,
    }
  }
}
