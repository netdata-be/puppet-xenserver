class xenserver (
  $rr_min_io = 100,
  $iscsi_MaxRecvDataSegmentLength = 262144,
  $iscsi_MaxBurstLength           = 16776192,
  $iscsi_MaxXmitDataSegmentLength = 0,
  $iscsi_FirstBurstLength         = 26144,
  $iscsi_HeaderDigest             = 'None',
  $iscsi_DataDigest               = 'None',
  $iscsi_MaxOutstandingR2T        = 1,
  $iscsi_InitialR2T               = 'No',
  $iscsi_ImmediateData            = 'Yes',



){

  user { 'qemu_base':
    ensure           => 'present',
    gid              => '65535',
    home             => '/none',
    password         => '!!',
    password_max_age => '99999',
    password_min_age => '0',
    shell            => '/bin/bash',
    uid              => '65535',
  }
  user { 'nfsnobody':
    ensure           => 'present',
    comment          => 'Anonymous NFS User',
    gid              => '65534',
    home             => '/var/lib/nfs',
    password         => '!!',
    password_max_age => '99999',
    password_min_age => '0',
    shell            => '/sbin/nologin',
    uid              => '65534',
  }
  user { 'vncterm_base':
    ensure           => 'present',
    gid              => '131072',
    home             => '/none',
    password         => '!!',
    password_max_age => '99999',
    password_min_age => '0',
    shell            => '/bin/bash',
    uid              => '131072',
  }
  group { 'vncterm_base':
    ensure => 'present',
    gid    => '131072',
  }
  group { 'nfsnobody':
    ensure => 'present',
    gid    => '65534',
  }
  group { 'qemu_base':
    ensure => 'present',
    gid    => '65535',
  }

  xenstore{ 'dom0':
    val => $::fqdn,
  }
  xenstore{ 'location':
    val => $location,
  }
  xenstore{ 'location_id':
    val => $location_id,
  }

  # Needed for nsupdate to update the DNS
  package{'bind-utils':
    ensure => installed,
  }

  file{'/etc/pam.d/system-auth':
    ensure => file,
    mode   => '0644',
    owner  => 'root',
    group  => 'root',
    source => "puppet:///modules/xenserver/system-auth",
    notify => Exec['pwconv'],
  }

  # If you add a file testing.txt to /usr/lib/xsconsole/ folder, Xsconsole starts in testing mode. If host=,
  # password= variables are defined in file testing.txt, xsconsole program authenticates on a remote server.
  # Besides, if xsconsole is used on tty1 local console, an attacker can access the local console with root
  # privileges. Therefore removing the file if it exist
  file{'/usr/lib/xsconsole/testing.txt':
    ensure => absent,
  }

  exec{'pwconv':
    refreshonly => true,
  }

  file {'/etc/multipath.conf':
    ensure  => file,
    mode    => '0777',
    owner   => 'root',
    group   => 'root',
    content => template("${module_name}/multipath.conf.erb"),
  }

  file {'/etc/iscsi/iscsid.conf':
    ensure  => file,
    mode    => '0600',
    owner   => 'root',
    group   => 'root',
    content => template("${module_name}/iscsid.conf.erb"),
  }

}
