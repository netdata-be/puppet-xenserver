require_relative '../../../xenapi/xenapi.rb'
require 'yaml'


Puppet::Type.type(:vm_instance).provide(:v2) do

  # This creates a bunch of getters/setters for our properties/parameters
  # this is only for prefetch/flush providers
  mk_resource_methods


	def self.xapi
  	@xapi ||= begin
	    verify    = :verify_none
			xapi_host = 'http://10'
	    password  = ''
	    username  = 'root'
	    session = XenApi::Client.new(xapi_host, 10, verify)
	    session.login_with_password(username, password)
	    session
		end
  end


  def initialize(value={})
    super(value)
    @property_flush = {} 
  end

  def self.instances
    instances = []

    vms = xapi.VM.get_all
    vms.collect do |vm|
      record = xapi.VM.get_record(vm)
      next if record['is_a_template']
      next if record['name_label'] =~ /control domain/i
      interfaces={}
			#puts record.to_yaml

      record['VIFs'].each do |vif|
        network = xapi.VIF.get_network(vif)
        device = xapi.VIF.get_device(vif)
        interfaces[device]=xapi.network.get_name_label(network)
      end

      if record['affinity'] == 'OpaqueRef:NULL'
        homeserver="auto"
      else
				puts "current homeserver"
				puts record['affinity']
        homeserver = xapi.host.get_name_label(record['affinity'])
      end

      vm_instance = {
        :name                   => record['name_label'],
				:vm_ref									=> vm,
        :ensure                 => :present,
        :state                  => record['power_state'],
        :desc                   => record['name_description'],
        :vcpus                  => record['VCPUs_at_startup'],
        :vcpus_max              => record['VCPUs_max'],
        :actions_after_shutdown => record['actions_after_shutdown'],
        :actions_after_reboot   => record['actions_after_reboot'],
        :actions_after_crash    => record['actions_after_crash'],
        :ram                    => record['memory_static_max'],
        :interfaces             => interfaces,
        :cores_per_socket       => record['platform']['cores-per-socket'],
        :homeserver             => homeserver,
        :provider               => self.name
      }
      instances << new(vm_instance)
    end

    return instances

  end

	def vcpus_max=(value)
    @property_flush[:vcpus_max] = value
  end

	def vcpus=(value)
    @property_flush[:vcpus] = value
  end

	def homeserver=(value)
    @property_flush[:homeserver] = value
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

	def flush
		xapi=Puppet::Type::Vm_instance::ProviderV2::xapi
    if @property_flush
			if @property_flush[:vcpus_max]
				xapi.VM.set_VCPUs_max(@property_hash[:vm_ref], @property_flush[:vcpus_max])
				@property_hash[:vcpus_max]=@property_flush[:vcpus_max]
			end
			if @property_flush[:vcpus]
				xapi.VM.set_VCPUs(@property_hash[:vm_ref], @property_flush[:vcpus])
				@property_hash[:vcpus]=@property_flush[:vcpus]
			end
			if @property_flush[:homeserver]
				if @property_flush[:homeserver] == "auto"
					xapi.VM.set_affinity(@property_hash[:vm_ref], 'OpaqueRef:NULL')
				else
					homeserver_ref = xapi.host.get_by_name_label(@property_flush[:homeserver])
					puts homeserver_ref
					puts @property_hash[:vm_ref]
					xapi.VM.set_affinity(homeserver_ref, @property_hash[:vm_ref])
				end
			end
		end
	end

end
