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
  String $container_ip = '172.16.0.2',
) {
  file { ["${datadir}/data", "${datadir}/provisioning", "${datadir}/certs"]:
    ensure => directory,
  }

  -> file { "${datadir}/grafana.ini":
    ensure  => file,
    content => template('grafana/grafana.ini.erb'),
  }

  -> acme::certificate { $hostname:
    reloadcmd      => '/usr/bin/systemctl restart container@grafana',
    keypath        => "${datadir}/certs/key",
    fullchainpath  => "${datadir}/certs/cert",
    account        => $tls_account,
    challengealias => $tls_challengealias,
  }

  -> firewall { '100 snat for network foo2':
    chain  => 'POSTROUTING',
    jump   => 'DNAT',
    proto  => 'tcp',
    dport  => 443,
    todest => "${container_ip}:3000",
    table  => 'nat',
  }

  -> docker::container { 'grafana':
    image => 'grafana/grafana-oss:latest',
    args  => [
      "--ip ${container_ip}",
      "-v ${datadir}/data:/var/lib/grafana",
      "-v ${datadir}/provisioning:/etc/grafana/provisioning",
      "-v ${datadir}/grafana.ini:/etc/grafana/grafana.ini",
      "-v ${datadir}/certs:/mnt/certs",
    ],
    cmd   => '',
  }
}
