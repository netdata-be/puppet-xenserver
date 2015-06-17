require_relative '../../../xenapi/xenapi.rb'
require 'yaml'


Puppet::Type.type(:vm_instance).provide(:vms) do

  # This creates a bunch of getters/setters for our properties/parameters
  # this is only for prefetch/flush providers
  mk_resource_methods


  def self.xapi
    @xapi ||= begin
      verify    = :verify_none
      xapi_host = 'http://10.12.12.34'
      password  = 'Vasco123.'
      username  = 'root'
      session = XenApi::Client.new(xapi_host, 10, verify)
      session.login_with_password(username, password)
      session
    end
  end

  at_exit {
    xapi.logout()
  }


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
      vifs={}

      record['VIFs'].each do |vif|
        network = xapi.VIF.get_network(vif)
        device = xapi.VIF.get_device(vif)
        vifs[device]=vif
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
        :vm_ref                  => vm,
        :ensure                 => :present,
        :state                  => record['power_state'],
        :desc                   => record['name_description'], # Done
        :vcpus                  => record['VCPUs_at_startup'], # done
        :vcpus_max              => record['VCPUs_max'], #done
        :actions_after_shutdown => record['actions_after_shutdown'], #done
        :actions_after_reboot   => record['actions_after_reboot'], #done
        :actions_after_crash    => record['actions_after_crash'], #done
        :ram                    => record['memory_static_max'], # done
        :interfaces             => interfaces, #done
        :vifs                   => vifs, #done
        :cores_per_socket       => record['platform']['cores-per-socket'],
        :homeserver             => homeserver, #broke ?
        :provider               => self.name
      }
      instances << new(vm_instance)
    end

    return instances

  end

  def vcpus_max=(value)
    @property_flush[:vcpus_max] = value
  end

  def ram=(value)
    @property_flush[:ram] = value
  end

  def vcpus=(value)
    @property_flush[:vcpus] = value
  end

  def actions_after_shutdown=(value)
    @property_flush[:actions_after_shutdown] = value
  end

  def actions_after_reboot=(value)
    @property_flush[:actions_after_reboot] = value
  end

  def actions_after_crash=(value)
    @property_flush[:actions_after_crash] = value
  end

  def desc=(value)
    @property_flush[:desc] = value
  end

  def interfaces=(value)
    @property_flush[:interfaces] = value
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

  # generate a random mac address
  def generate_mac
    ('%02x' % (rand(64) * 4 | 2)) + (0..4).reduce('') { |s, _x|s + ':%02x' % rand(256) }
  end

  def flush
    xapi=self.class.xapi
    return unless @property_flush

    case
      when @property_flush[:vcpus_max]
        xapi.VM.set_VCPUs_max(@property_hash[:vm_ref], @property_flush[:vcpus_max])
        @property_hash[:vcpus_max]=@property_flush[:vcpus_max]

      when @property_flush[:actions_after_shutdown]
        xapi.VM.set_actions_after_shutdown(@property_hash[:vm_ref], @property_flush[:actions_after_shutdown])
        @property_hash[:actions_after_shutdown]=@property_flush[:actions_after_shutdown]

      when @property_flush[:actions_after_crash]
        xapi.VM.set_actions_after_crash(@property_hash[:vm_ref], @property_flush[:actions_after_crash])
        @property_hash[:actions_after_crash]=@property_flush[:actions_after_crash]

      when @property_flush[:actions_after_shutdown]
        xapi.VM.set_actions_after_shutdown(@property_hash[:vm_ref], @property_flush[:actions_after_shutdown])
        @property_hash[:actions_after_shutdown]=@property_flush[:actions_after_shutdown]

      when @property_flush[:vcpus]
        xapi.VM.set_VCPUs(@property_hash[:vm_ref], @property_flush[:vcpus])
        @property_hash[:vcpus]=@property_flush[:vcpus]

      when @property_flush[:desc]
        xapi.VM.set_name_description(@property_hash[:vm_ref], @property_flush[:desc])
        @property_hash[:desc]=@property_flush[:desc]

      when @property_flush[:interfaces]




      when @property_flush[:ram]  &&  @property_flush[:ram] > @property_hash[:ram]
        xapi.VM.set_memory_static_max(@property_hash[:vm_ref], @property_flush[:ram])
        xapi.VM.set_memory_dynamic_max(@property_hash[:vm_ref], @property_flush[:ram])
        xapi.VM.set_memory_dynamic_min(@property_hash[:vm_ref], @property_flush[:ram])
        xapi.VM.set_memory_static_min(@property_hash[:vm_ref], @property_flush[:ram])
        @property_hash[:ram]=@property_flush[:ram]

      when @property_flush
        xapi.VM.set_memory_static_min(@property_hash[:vm_ref], @property_flush[:ram])
        xapi.VM.set_memory_dynamic_min(@property_hash[:vm_ref], @property_flush[:ram])
        xapi.VM.set_memory_dynamic_max(@property_hash[:vm_ref], @property_flush[:ram])
        xapi.VM.set_memory_static_max(@property_hash[:vm_ref], @property_flush[:ram])
        @property_hash[:ram]=@property_flush[:ram]

      when @property_flush[:homeserver] &&  @property_flush[:homeserver] == "auto"
        xapi.VM.set_affinity(@property_hash[:vm_ref], 'OpaqueRef:NULL')

      when @property_flush[:homeserver]
        homeserver_ref = xapi.host.get_by_name_label(@property_flush[:homeserver])
        puts homeserver_ref
        puts @property_hash[:vm_ref]
        xapi.VM.set_affinity(homeserver_ref, @property_hash[:vm_ref])

    end
  end
end
