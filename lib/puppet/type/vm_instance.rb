require_relative '../../xenapi/xenapi.rb'

Puppet::Type.newtype(:vm_instance) do
    @doc = 'Type representing an xenserver vm instance.'


  ensurable

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

  newproperty(:state) do
    desc 'How much RAM does the machine have.'
  end

  newproperty(:desc) do
    desc 'Description of the VM.'
  end

  newproperty(:vcpus) do
    desc 'How much virtual CPUs should the vm have.'
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
