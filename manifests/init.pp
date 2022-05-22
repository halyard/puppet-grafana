# @summary Configure Grafana instance
#
# @param hostname sets the hostname for grafana
# @param datadir sets where the data is persisted
# @param tls_account sets the TLS account config
# @param tls_challengealias sets the alias for TLS cert
class grafana (
  String $hostname,
  String $datadir,
  String $tls_account,
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
