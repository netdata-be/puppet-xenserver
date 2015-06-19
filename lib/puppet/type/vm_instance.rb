require_relative '../../xenapi/xenapi.rb'
require 'pry'

Puppet::Type.newtype(:vm_instance) do
    @doc = 'Type representing an xenserver vm instance.'


  newproperty(:ensure) do
    newvalue(:present) do
      #  provider.create unless provider.running?
      provider.running
    end

    newvalue(:stopped) do
      #provider.stop unless provider.stopped?
      provider.stopped
    end

    newvalue(:absent) do
      provider.destroy if provider.exists?
    end

    newvalue(:running) do
      #provider.create unless provider.running?
      provider.running
    end

  end

  newproperty(:vifs) do
    desc 'The virtual interfaces ID.'
    validate do |value|
      fail 'vifs is read-only'
    end
  end

  newproperty(:vm_ref) do
    desc 'The virtual machine ref.'
    validate do |value|
      fail 'vm_ref is read-only'
    end
  end


  newparam(:name, namevar: true) do
    desc 'The name of the instance.'
    validate do |value|
      fail 'Instances must have a name' if value == ''
      fail 'name should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:ram) do
    desc 'How much RAM does the machine have.'
  end

  newproperty(:memory_dynamic_min) do
    desc 'Todo'
  end

  newproperty(:memory_static_min) do
    desc 'Defaults to 256MB'
    defaultto '268435456'
  end

  newproperty(:memory_static_max) do
    desc 'Defaults to 16G'
    defaultto '16106127360'
  end


  newproperty(:desc) do
    desc 'Description of the VM.'
  end

  newproperty(:vcpus) do
    desc 'How much virtual CPUs should the vm have.'
    defaultto '2'
  end

  newproperty(:actions_after_shutdown) do
    desc 'What should xenserver do after a shutdown.'
    defaultto "destroy"
  end

  newproperty(:actions_after_reboot) do
    desc 'What should xenserver do after a reboot.'
    defaultto "restart"
  end

  newproperty(:actions_after_crash) do
    desc 'What should xenserver do after a crash.'
    defaultto "restart"
  end

  newproperty(:vcpus_max) do
    desc 'Whats the max Virtual CPUs in the VM.'
    defaultto "16"
  end

  newproperty(:disks, :array_matching => :all) do
    desc 'The disks added to the vm.'

    def insync?(is)
      is.to_s == should.to_s
    end

    munge do |value|

      value_split = value.split(':')

      # Convert the size to a consecent value
      case value_split[1]
        when /\d+\.?(\d+)?t|\d+\.?(\d+)?tb|\d+\.?(\d+)?tib/i
          size="#{value_split[1].to_f}TB"
        when /\d+\.?(\d+)?m|\d+\.?(\d+)?mb|\d+\.?(\d+)?kib/i
          size="#{value_split[1].to_f}MB"
        when /\d+\.?(\d+)?kb|\d+\.?(\d+)?kib/i
          size="#{split[1].to_f}KB"
        when /\d+\.?(\d+)?b/i
          size="#{value_split[1].to_f}B"
        else
          size="#{value_split[1].to_f}GB"
      end

      if value_split != "#{@resource[:name]}-#{value_split[0]}"
        name = "#{@resource[:name]}-#{value_split[0]}"
        value_split[0]=name
      end

      Puppet.debug(value.inspect)
      value_split[1]=size
      value=value_split.join(':')
      Puppet.debug(value.inspect)
    end
  end

  newparam(:debian_preseed) do
    desc 'This is the debian installer preseed.'
    defaultto "http://10.12.12.35/wheezy-preseed.cfg"
  end

  newparam(:ip_address) do
    desc 'The initial IP for the VM, can also be dhcp.'
    defaultto "dhcp"
  end

  newparam(:netmask) do
    desc 'The netmask of the vm.'
    defaultto "255.255.255.0"
  end

  newparam(:nameserver) do
    desc 'The nameserver of the vm.'
    defaultto "8.8.8.8"
  end

  newparam(:gateway) do
    desc 'The gateway of the vm'
  end

  newparam(:debian_repo) do
    desc 'The repo to install debian from'
    defaultto "http://ftp.be.debian.org/debian/"
  end

  newproperty(:cores_per_socket) do
    desc 'Amount of cores per socket'
    defaultto "1"
  end

  newproperty(:homeserver) do
    desc 'The homeserver of this VM'
    defaultto "auto"
  end

  newproperty(:interfaces) do
    desc 'This is an array containing the names of the interfaces the VM has.'
  end

end
