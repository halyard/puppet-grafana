# @summary Configure Grafana instance
#
# @param hostname sets the hostname for grafana
# @param datadir sets where the data is persisted
# @param tls_account sets the TLS account config
# @param admin_user sets the username for the primary Grafana account
# @param admin_password sets the password for the primary Grafana account
# @param secret_key sets the AES key used for encrypting Grafana sessions
# @param client_id sets the Github OAuth client ID
# @param client_secret sets the Github OAuth client secret
# @param tls_challengealias sets the alias for TLS cert
# @param root_domain sets the publicly visible root domain for the site
# @param root_url sets the publicly visible root URL for the site
# @param container_ip sets the address of the Docker container
# @param allowed_organizations sets the organization requirements for Github auth
# @param team_ids sets the team requirements for Github auth
# @param plugins sets the plugins to install
# @param extra_config sets extra grafana config flags to use
# @param backup_target sets the target repo for backups
# @param backup_watchdog sets the watchdog URL to confirm backups are working
# @param backup_password sets the encryption key for backup snapshots
# @param backup_environment sets the env vars to use for backups
# @param backup_rclone sets the config for an rclone backend
class grafana (
  String $hostname,
  String $datadir,
  String $tls_account,
  String $admin_user,
  String $admin_password,
  String $secret_key,
  String $client_id,
  String $client_secret,
  Optional[String] $tls_challengealias = undef,
  Optional[String] $root_domain = undef,
  Optional[String] $root_url = undef,
  String $container_ip = '172.17.0.2',
  Array[String] $allowed_organizations = [],
  Array[String] $team_ids = [],
  Array[String] $plugins = [],
  Array[String] $extra_config = [],
  Optional[String] $backup_target = undef,
  Optional[String] $backup_watchdog = undef,
  Optional[String] $backup_password = undef,
  Optional[Hash[String, String]] $backup_environment = undef,
  Optional[String] $backup_rclone = undef,
) {
  file { [$datadir, "${datadir}/data", "${datadir}/provisioning", "${datadir}/certs"]:
    ensure => directory,
  }

  -> file { "${datadir}/grafana.ini":
    ensure  => file,
    content => template('grafana/grafana.ini.erb'),
    notify  => Service['container@grafana'],
  }

  -> acme::certificate { $hostname:
    reloadcmd      => '/usr/bin/systemctl restart container@grafana',
    keypath        => "${datadir}/certs/key",
    fullchainpath  => "${datadir}/certs/cert",
    account        => $tls_account,
    challengealias => $tls_challengealias,
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

  if $backup_target != '' {
    backup::repo { 'grafana':
      source        => "${datadir}/data",
      target        => $backup_target,
      watchdog_url  => $backup_watchdog,
      password      => $backup_password,
      environment   => $backup_environment,
      rclone_config => $backup_rclone,
    }

    backup::repo { 'grafana-provisioning':
      source        => "${datadir}/provisioning",
      target        => $backup_target,
      watchdog_url  => $backup_watchdog,
      password      => $backup_password,
      environment   => $backup_environment,
      rclone_config => $backup_rclone,
    }
  }
}
