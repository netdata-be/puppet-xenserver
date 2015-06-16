require_relative '../../../xenapi/xenapi.rb'
require 'yaml'


Puppet::Type.type(:vm_instance).provide(:v2) do

 mk_resource_methods

    verify = :verify_none
    @session = XenApi::Client.new('https://x.x.x.x', 10, verify)
    @session.login_with_password('root', 'xxxx')

  def initialize(value={})
    super(value)
    @property_flush = {}

    # first create a connection and login
  end

  def self.instances
    instances = []

    vms = @session.VM.get_all
    vms.collect do |vm|
      record = @session.VM.get_record(vm)
      next if record['is_a_template']
      next if record['name_label'] =~ /control domain/i
      interfaces={}

      record['VIFs'].each do |vif|
        network = @session.VIF.get_network(vif)
        device = @session.VIF.get_device(vif)
        interfaces[device]=@session.network.get_name_label(network)
      end

      if record['affinity'] == 'OpaqueRef:NULL'
        homeserver="auto"
      else
        homeserver = @session.host.get_name_label(record['affinity'])
      end

      vm_instance = {
        :name => record['name_label'],
        :ensure => :present,
        :state => record['power_state'],
        :desc => record['name_description'],
        :vcpus => record['VCPUs_at_startup'],
        :vcpus_max => record['VCPUs_max'],
        :actions_after_shutdown => record['actions_after_shutdown'],
        :actions_after_reboot => record['actions_after_reboot'],
        :actions_after_crash => record['actions_after_crash'],
        :ram => record['memory_static_max'],
        :interfaces => interfaces,
        :cores_per_socket => record['platform']['cores-per-socket'],
        :homeserver => homeserver,
        :provider => self.name
      }
      instances << new(vm_instance)
    end

    return instances

  end

  def exists?
      @property_hash[:ensure] == :present
  end

  def create
    @property_flush[:ensure] = :present
  end


  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov
      end
    end
  end

end
