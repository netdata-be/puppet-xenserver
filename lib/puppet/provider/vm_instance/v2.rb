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

      record['power_state'] = "stopped" if record['power_state'].downcase == "halted"

      vm_instance = {
        :name                   => record['name_label'],
        :vm_ref                 => vm,
        :ensure                 => record['power_state'].downcase,
        :desc                   => record['name_description'], # Done
        :vcpus                  => record['VCPUs_at_startup'], # done
        :vcpus_max              => record['VCPUs_max'], #done
        :actions_after_shutdown => record['actions_after_shutdown'], #done
        :actions_after_reboot   => record['actions_after_reboot'], #done
        :actions_after_crash    => record['actions_after_crash'], #done
        :ram                    => record['memory_dynamic_max'], 
        :memory_dynamic_min     => record['memory_dynamic_min'],
        :memory_static_max      => record['memory_static_max'],
        :memory_static_min      => record['memory_static_min'],    
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
    case @property_hash[:ensure]
      when /stopped|running/
        true
      else
        false
    end
  end

  def create
    puts "Calling create"
  end

  def destroy
    @property_flush[:ensure] = :absent
  end

  def stopped
    @property_flush[:ensure] = :stopped
  end

  def running
    @property_flush[:ensure] = :running
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

  # sit and wait for taks to exit pending state
  def wait_on_task(task)
    xapi=self.class.xapi
    while xapi.task.get_status(task) == 'pending'
      xapi.task.get_progress(task)
      sleep 1
    end
  end

  def flush
    xapi=self.class.xapi
    Puppet.debug("hihi 1")
    return unless @property_flush

    if @property_flush[:ensure]
      case @property_flush[:ensure]
        when :present
          Puppet.info("Calling present")
          puts "Calling present"
        when :running
          if @property_hash[:ensure] == "stopped"
            Puppet.debug("vm (#{@property_hash[:name]}) waiting to start VM")
            #task = xapi.Async.VM.start(@property_hash[:vm_ref],false,true)
						xapi.VM.start(@property_hash[:vm_ref],false,true)
            #wait_on_task(task)
            #Puppet.debug("vm (#{@property_hash[:name]}) vm should be started")
            @property_hash[:ensure]=@property_flush[:ensure]
          else
            Puppet.debug("vm (#{@property_hash[:name]}) is not in a stopped state, state=#{@property_hash[:ensure]}")
          end
        when :halted
          if @property_hash[:ensure] == "running"
            Puppet.debug("vm (#{@property_hash[:name]}) is running, sending clean shutdown command")
            task = xapi.Async.VM.clean_shutdown(@property_hash[:vm_ref])
            Puppet.debug("vm (#{@property_hash[:name]}) Waiting on shutdown")
            wait_on_task(task)

            Puppet.debug("vm (#{@property_hash[:name]}) Sending hard_shutdown for in case the VM is still running")
            task = xapi.Async.VM.hard_shutdown(@property_hash[:vm_ref])
            wait_on_task(task)
          else
            Puppet.debug("vm (#{@property_hash[:name]}) is not in a Running state, so nothing is required")
          end
        when :absent
          if @property_hash[:ensure] == "running"
            Puppet.debug("vm (#{@property_hash[:name]}) is running, sending clean shutdown command")
            task = xapi.Async.VM.clean_shutdown(@property_hash[:vm_ref])
            Puppet.debug("vm (#{@property_hash[:name]}) Waiting on shutdown")
            wait_on_task(task)

            Puppet.debug("vm (#{@property_hash[:name]}) Sending hard_shutdown for in case the VM is still running")
            task = xapi.Async.VM.hard_shutdown(@property_hash[:vm_ref])
            wait_on_task(task)

        end
        # Remove the VM
        # TODO Also remove the disks
        xapi.VM.destroy(@property_hash[:vm_ref])
      end
    end

    Puppet.debug("hihi 3")
    if @property_flush[:vcpus_max]
      if @property_hash[:ensure] == "halted"
        xapi.VM.set_VCPUs_max(@property_hash[:vm_ref], @property_flush[:vcpus_max])
        @property_hash[:vcpus_max]=@property_flush[:vcpus_max]
      else
       err "Can't change vcpus_max while running, please stop VM in order to adjust"
      end
    end

    Puppet.debug("hihi 4")
    if @property_flush[:actions_after_shutdown]
      xapi.VM.set_actions_after_shutdown(@property_hash[:vm_ref], @property_flush[:actions_after_shutdown])
      @property_hash[:actions_after_shutdown]=@property_flush[:actions_after_shutdown]
    end

    Puppet.debug("hihi 5")
    if @property_flush[:actions_after_crash]
      xapi.VM.set_actions_after_crash(@property_hash[:vm_ref], @property_flush[:actions_after_crash])
      @property_hash[:actions_after_crash]=@property_flush[:actions_after_crash]
    end

    Puppet.debug("hihi 6")
    if @property_flush[:actions_after_shutdown]
      xapi.VM.set_actions_after_shutdown(@property_hash[:vm_ref], @property_flush[:actions_after_shutdown])
      @property_hash[:actions_after_shutdown]=@property_flush[:actions_after_shutdown]
    end

    Puppet.debug("hihi 7")
    if @property_flush[:vcpus]
      xapi.VM.set_VCPUs_at_startup(@property_hash[:vm_ref], @property_flush[:vcpus])
      xapi.VM.set_VCPUs_number_live(@property_hash[:vm_ref], @property_flush[:vcpus])
      @property_hash[:vcpus]=@property_flush[:vcpus]
    end

    Puppet.debug("hihi 8")
    if @property_flush[:desc]
      xapi.VM.set_name_description(@property_hash[:vm_ref], @property_flush[:desc])
      @property_hash[:desc]=@property_flush[:desc]
    end

    Puppet.debug("hihi 9")
    if @property_flush[:interfaces]
      interfaces=@property_flush[:interfaces]
      interfaces.each do |device_id, name|
        next if @property_hash[:interfaces][device_id] == name
        Puppet.debug("Looking up network_ref for: #{name}")
        network_ref = xapi.network.get_by_name_label(name).first
        Puppet.debug(" => #{name} => #{network_ref}")
        if network_ref.nil?
          Puppet.error("Network #{name} not found in xen")
          next
        end
        if @property_hash[:vifs][device_id] && @property_hash[:interfaces][device_id] != name
          Puppet.debug("Device with ID #{device_id} already exist, going to remove it")
          vif_ref = @property_hash[:vifs][device_id]
          xapi.VIF.destroy(vif_ref)
        end
        vif = {
          'device'  => device_id,
          'network' => network_ref,
          'VM'  => @property_hash[:vm_ref],
          'MAC' => generate_mac,
          'MTU' => '1500',
          'other_config' => {},
          'qos_algorithm_type'   => '',
          'qos_algorithm_params' => {}
        }
        vif_ref = xapi.VIF.create(vif)
      end

      # Now find vifs which are not configred and remove them
      @property_hash[:vifs].each do |device_id, vif_ref|
        next if @property_flush[:interfaces][device_id]
        Puppet.debug("Device found which should be removed with ID #{vif_ref}")
        xapi.VIF.destroy(vif_ref)
      end
    end


    Puppet.debug("hihi 10")

    if @property_flush[:memory_static_min]
      if @property_hash[:ensure] == "halted"
        xapi.VM.set_memory_static_min(@property_hash[:vm_ref], @property_flush[:memory_static_min])
        @property_hash[:vcpus_max]=@property_flush[:vcpus_max]
      else
       err "Can't change memory_static_min while running, please stop VM in order to adjust"
      end
    end

    if @property_flush[:memory_static_max]
      if @property_hash[:ensure] == "halted"
        xapi.VM.set_memory_static_max(@property_hash[:vm_ref], @property_flush[:memory_static_max])
        @property_hash[:vcpus_max]=@property_flush[:vcpus_max]
      else
       err "Can't change memory_static_max while running, please stop VM in order to adjust"
      end
    end

    if @property_flush[:ram] && @property_flush[:ram] > @property_hash[:ram]
      Puppet.debug("1")
      # Give the VM the amount of ram configred
      xapi.VM.set_memory_dynamic_max(@property_hash[:vm_ref], @property_flush[:ram])
      Puppet.debug("2")
      # Calculate the min dynamic allocation based on a percentage of memory_dynamic_max
      dynamic_min=(@property_flush[:ram].to_i*(70.0/100)).round
      Puppet.debug("mem_dyn_min is set 70% of the configured RAM = #{dynamic_min.to_s}")
      xapi.VM.set_memory_dynamic_min(@property_hash[:vm_ref], dynamic_min.to_s)
      Puppet.debug("3")
      @property_hash[:ram]=@property_flush[:ram]
      @property_hash[:memory_dynamic_mim]=dynamic_min
    end

    if @property_flush[:ram] && @property_flush[:ram] < @property_hash[:ram]
      Puppet.debug("1.1")
      # Calculate the min dynamic allocation based on a percentage of memory_dynamic_max
      dynamic_min=(@property_flush[:ram].to_i*(70.0/100)).round
      Puppet.debug("mem_dyn_min is set 70% of the configured RAM = #{dynamic_min.to_s}")
      xapi.VM.set_memory_dynamic_min(@property_hash[:vm_ref], dynamic_min.to_s)
      Puppet.debug("2.2")
      # Give the VM the amount of ram configred
      xapi.VM.set_memory_dynamic_max(@property_hash[:vm_ref], @property_flush[:ram])
      Puppet.debug("3.3")
      @property_hash[:ram]=@property_flush[:ram]
      @property_hash[:memory_dynamic_mim]=dynamic_min
    end


    Puppet.debug("hihi 11")
    Puppet.debug("hihi 12")
    if @property_flush[:homeserver] &&  @property_flush[:homeserver] == "auto"
      xapi.VM.set_affinity(@property_hash[:vm_ref], 'OpaqueRef:NULL')
    end

    Puppet.debug("hihi 13")
    if @property_flush[:homeserver] &&  @property_flush[:homeserver] != "auto"
      homeserver_ref = xapi.host.get_by_name_label(@property_flush[:homeserver])
      puts homeserver_ref
      puts @property_hash[:vm_ref]
      xapi.VM.set_affinity(homeserver_ref, @property_hash[:vm_ref])
    end

  end
end
