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

  -> docker::container { 'grafana':
    image => 'grafana/grafana-oss:latest',
    args  => [
      '-p 443:3000',
      "-v ${datadir}/data:/var/lib/grafana",
      "-v ${datadir}/provisioning:/etc/grafana/provisioning",
      "-v ${datadir}/grafana.ini:/etc/grafana/grafana.ini",
      "-v ${datadir}/certs:/mnt/certs",
    ],
    cmd   => '',
  }
}
