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

  # convert 1g/1m/1t to bytes
  # rounds to whole numbers
  def input_to_bytes(size)
    case size
    when /m|mb/i
      size.to_i * (1024**2)
    when /t|tb/i
      size.to_i * (1024**4)
    else
      # default is gigabytes
      size.to_i * (1024**3)
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

  def get_task_ref(task)
    xapi=self.class.xapi
    wait_on_task(task)
    case xapi.task.get_status(task)
      when "success"
        # xapi task record returns result as  <value>OpaqueRef:....</value>  
        # we want the ref. this way it will work if they fix it to return jsut the ref
        ref = xapi.task.get_result(task).match(/OpaqueRef:[^<]+/).to_s
        #cleanup our task
        xapi.task.destroy(task)
        return ref
      else
        err "Task returned: #{xapi.task.get_result(task)}"
        return nil
      end
    end

  # create a vdi return ref
  def create_vdi(name, sr_ref, size, desc)
    xapi=self.class.xapi
    vdi_record = {
      'name_label' => "#{name}",
      'name_description' => desc,
      'SR' => sr_ref,
      'virtual_size' => input_to_bytes(size).to_s,
      'type' => 'system',
      'sharable' => false,
      'read_only' => false,
      'other_config' => {}
    }

    # Async create the VDI
    task = xapi.Async.VDI.create(vdi_record)
    Puppet.debug('waiting for VDI Create')
    vdi_ref = get_task_ref(task)
    vdi_ref
  end

  def create_networks(vm_ref, interfaces)
    xapi=self.class.xapi
    Puppet.debug("hash = #{@property_hash.class}")
    Puppet.debug("hash = #{@property_hash.inspect}")

    Puppet.debug("interfaces = #{interfaces.inspect}")
    interfaces.each do |device_id, name|
      if ! @property_hash.empty?
        next if @property_hash[:interfaces][device_id] == name
      end
      Puppet.debug("Looking up network_ref for: #{name}")
      network_ref = xapi.network.get_by_name_label(name).first
      Puppet.debug(" => #{name} => #{network_ref}")
      if network_ref.nil?
        Puppet.error("Network #{name} not found in xen")
        next
      end
      if ! @property_hash.empty?
        if @property_hash[:vifs][device_id] && @property_hash[:interfaces][device_id] != name
          Puppet.debug("Device with ID #{device_id} already exist, going to remove it")
          vif_ref = @property_hash[:vifs][device_id]
          xapi.VIF.destroy(vif_ref)
        end
      end
      vif = {
        'device'  => device_id,
        'network' => network_ref,
        'VM'  => vm_ref,
        'MAC' => generate_mac,
        'MTU' => '1500',
        'other_config' => {},
        'qos_algorithm_type'   => '',
        'qos_algorithm_params' => {}
      }
      vif_ref = xapi.VIF.create(vif)
    end


    if ! @property_hash.empty?
      # Now find vifs which are not configred and remove them
      @property_hash[:vifs].each do |device_id, vif_ref|
        next if @interfaces[:interfaces][device_id]
        Puppet.debug("Device found which should be removed with ID #{vif_ref}")
        xapi.VIF.destroy(vif_ref)
      end
    end
  end

  # create vbd and return a ref
  # defaults to bootable
  def create_vbd(vm_ref, vdi_ref, position, boot = true)
    xapi=self.class.xapi
    vbd_record = {
      'VM' => vm_ref,
      'VDI' => vdi_ref,
      'empty' => false,
      'other_config' => { 'owner' => '' },
      'userdevice' => position.to_s,
      'bootable' => boot,
      'mode' => 'RW',
      'qos_algorithm_type' => '',
      'qos_algorithm_params' => {},
      'qos_supported_algorithms' => [],
      'type' => 'Disk'
    }

    task = xapi.Async.VBD.create(vbd_record)
    Puppet.debug('Waiting for VBD create')
    vbd_ref = get_task_ref(task)
    vbd_ref
  end


  def create
    xapi=self.class.xapi

    # Lookup the template ref for our VM
    template_ref = xapi.VM.get_by_name_label('Debian Wheezy 7.0 (64-bit)').first
    if template_ref.empty? || template_ref.nil?
      err " No template found with that name"
    end
    Puppet.debug("template_ref = #{template_ref}")

    sr_ref = xapi.SR.get_by_name_label('iSCSI SAS RAID6').first
    if sr_ref.empty? || sr_ref.nil?
      err " No storage REPO found with that name"
    end
    Puppet.debug("sr_ref = #{template_ref}")

    Puppet.debug("vm (#{@resource[:name]}) Cloning template into VM")
    task = xapi.Async.VM.copy(template_ref, @resource[:name], sr_ref )
    Puppet.debug("vm (#{@resource[:name]}) Waiting on template clone")
    vm_ref = get_task_ref(task)
    Puppet.debug("vm_ref = #{vm_ref}")

    begin
      xapi.VM.set_name_description(vm_ref, "VM crete by puppet as #{resource[:name]}")

      # make sure we don't clobber existing params
      other_config = {}
      record = xapi.VM.get_record(vm_ref)
      if record.key? 'other_config'
        other_config = record['other_config']
      end
      other_config['install-repository'] = @resource[:debian_repo]

      # remove any disk config/xml template might be trying to do (ubuntu)
      other_config.delete_if {|k,v| k=="disks"}

      Puppet.debug("Setting other_config")
      xapi.VM.set_other_config(vm_ref, other_config)

      Puppet.debug("Setting VCPUs_max")
      xapi.VM.set_VCPUs_max(vm_ref, @resource[:vcpus_max])
      Puppet.debug("Setting mem_stat_max")
      xapi.VM.set_memory_static_max( vm_ref, @resource[:memory_static_max])
      Puppet.debug("Setting mem_stat_min")
      xapi.VM.set_memory_static_min( vm_ref, @resource[:memory_static_min])
      Puppet.debug("Setting vcpus")
      xapi.VM.set_VCPUs_at_startup( vm_ref , @resource[:vcpus])

      # Now create the disks
      
      @resource[:disks].each do |disk|
      end

      vdi_ref = create_vdi("#{@resource[:name]}-root", sr_ref, @resource[:disksize], 'Root disk created by puppet')
      position == 0 ?  bootable = true : bootable = false
      vbd_ref = create_vbd(vm_ref, vdi_ref, position, bootable)
      create_networks(vm_ref, resource[:interfaces])

      Puppet.debug("provision")
      provisioned = xapi.VM.provision(vm_ref)

      #
      # setup the PV args
      #
      pv_args  = " netcfg/get_hostname=#{resource[:name]}"
      pv_args << " netcfg/get_domain=vm.vcloud"
      pv_args << " netcfg/get_domain=vm.vcloud"
      pv_args << " console=hvc0"
      pv_args << " debian-installer/locale=en_US"
      pv_args << " debian-installer/language=en"
      pv_args << " console-setup/layoutcode=us"
      pv_args << " console-keymaps-at/keymap=us"
      pv_args << " console-setup/ask_detect=false"
      pv_args << " console-keymaps-at/keymap=us"
      pv_args << " console-setup/ask_detect=false"
      pv_args << " console-tools/archs=skip-config"
      pv_args << " keyboard-configuration/xkb-keymap=us"
      pv_args << " keyboard-configuration/layoutcode=us"
      pv_args << " interface=eth0"
      pv_args << " locale=en_US"
      pv_args << " debian-installer/country=BE"
      pv_args << " preseed/url=#{@resource[:debian_preseed]}"

      if @resource[:ip_address] == 'dhcp'
        pv_args << " netcfg/disable_dhcp=false"
      else
        pv_args << " netcfg/get_ipaddress=#{@resource[:ip_address]}"
        pv_args << " netcfg/get_netmask=#{@resource[:netmask]}"
        pv_args << " netcfg/get_gateway=#{@resource[:gateway]}"
        pv_args << " netcfg/get_nameservers=#{@resource[:nameserver]}"
        pv_args << " netcfg/disable_dhcp=true"
      end

      Puppet.debug("Setting kernel parameters")
      xapi.VM.set_PV_args(vm_ref, pv_args)

      Puppet.debug("provisioned = #{provisioned.inspect}")
      task = xapi.Async.VM.start(vm_ref,false,true)
      Puppet.debug("vm (#{@resource[:name]}) Waiting to start")
      wait_on_task(task)
    end

  end

  def flush
    xapi=self.class.xapi
    return unless @property_flush

    Puppet.debug("Stage 1")
    if @property_flush[:ensure]
      case @property_flush[:ensure]
        when :present
          Puppet.info("Calling present")
          puts "Calling present"
        when :running
          if exists?
            if @property_hash[:ensure] == "stopped"
              Puppet.debug("vm (#{@property_hash[:name]}) waiting to start VM")
              task = xapi.Async.VM.start(@property_hash[:vm_ref],false,true)
              wait_on_task(task)
              Puppet.debug("vm (#{@property_hash[:name]}) vm should be started")
              @property_hash[:ensure]=@property_flush[:ensure]
              @property_hash[:ensure]="running"
            else
              Puppet.debug("vm (#{@property_hash[:name]}) is not in a stopped state, state=#{@property_hash[:ensure]}")
            end
          else
            Puppet.debug("VM does not exist, create logic to create one")
            create

          end
        when :stopped
          if @property_hash[:ensure] == "running"
            Puppet.debug("vm (#{@property_hash[:name]}) is running, sending clean shutdown command")
            task = xapi.Async.VM.clean_shutdown(@property_hash[:vm_ref])
            Puppet.debug("vm (#{@property_hash[:name]}) Waiting on shutdown")
            wait_on_task(task)

            Puppet.debug("vm (#{@property_hash[:name]}) Sending hard_shutdown for in case the VM is still running")
            task = xapi.Async.VM.hard_shutdown(@property_hash[:vm_ref])
            wait_on_task(task)
            @property_hash[:ensure]="stopped"
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

    Puppet.debug("Stage 2")
    if @property_flush[:vcpus_max]
      if @property_hash[:ensure] == "halted"
        xapi.VM.set_VCPUs_max(@property_hash[:vm_ref], @property_flush[:vcpus_max])
        @property_hash[:vcpus_max]=@property_flush[:vcpus_max]
      else
       err "Can't change vcpus_max while running, please stop VM in order to adjust"
      end
    end

    Puppet.debug("Stage 2")
    if @property_flush[:actions_after_shutdown]
      xapi.VM.set_actions_after_shutdown(@property_hash[:vm_ref], @property_flush[:actions_after_shutdown])
      @property_hash[:actions_after_shutdown]=@property_flush[:actions_after_shutdown]
    end

    Puppet.debug("Stage 3")
    if @property_flush[:actions_after_crash]
      xapi.VM.set_actions_after_crash(@property_hash[:vm_ref], @property_flush[:actions_after_crash])
      @property_hash[:actions_after_crash]=@property_flush[:actions_after_crash]
    end

    Puppet.debug("Stage 4")
    if @property_flush[:actions_after_shutdown]
      xapi.VM.set_actions_after_shutdown(@property_hash[:vm_ref], @property_flush[:actions_after_shutdown])
      @property_hash[:actions_after_shutdown]=@property_flush[:actions_after_shutdown]
    end

    Puppet.debug("Stage 5")
    if @property_flush[:vcpus]
      xapi.VM.set_VCPUs_at_startup(@property_hash[:vm_ref], @property_flush[:vcpus])
      xapi.VM.set_VCPUs_number_live(@property_hash[:vm_ref], @property_flush[:vcpus])
      @property_hash[:vcpus]=@property_flush[:vcpus]
    end

    Puppet.debug("Stage 6")
    if @property_flush[:desc]
      xapi.VM.set_name_description(@property_hash[:vm_ref], @property_flush[:desc])
      @property_hash[:desc]=@property_flush[:desc]
    end

    Puppet.debug("Stage 7")
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



    Puppet.debug("Stage 8")
    if @property_flush[:memory_static_min]
      if @property_hash[:ensure] == "stopped"
        xapi.VM.set_memory_static_min(@property_hash[:vm_ref], @property_flush[:memory_static_min])
        @property_hash[:memory_static_min]=@property_flush[:memory_static_min]
      else
       err "Can't change memory_static_min while running, please stop VM in order to adjust"
      end
    end

    Puppet.debug("Stage 9")
    if @property_flush[:memory_static_max]
      if @property_hash[:ensure] == "stopped"
        xapi.VM.set_memory_static_max(@property_hash[:vm_ref], @property_flush[:memory_static_max])
        @property_hash[:memory_static_max]=@property_flush[:memory_static_max]
      else
       err "Can't change memory_static_max while running, please stop VM in order to adjust"
      end
    end

    Puppet.debug("Stage 10")
    if @property_flush[:ram] && @property_flush[:ram].to_i > @property_hash[:ram].to_i
      # Give the VM the amount of ram configred
      xapi.VM.set_memory_dynamic_max(@property_hash[:vm_ref], @property_flush[:ram])
      # Calculate the min dynamic allocation based on a percentage of memory_dynamic_max
      dynamic_min=(@property_flush[:ram].to_i*(70.0/100)).round
      Puppet.debug("mem_dyn_min is set 70% of the configured RAM = #{dynamic_min.to_s}")
      xapi.VM.set_memory_dynamic_min(@property_hash[:vm_ref], dynamic_min.to_s)

      @property_hash[:ram]=@property_flush[:ram]
      @property_hash[:memory_dynamic_mim]=dynamic_min
    end

    Puppet.debug("Stage 11")
    if @property_flush[:ram] && @property_flush[:ram].to_i < @property_hash[:ram].to_i
      # Calculate the min dynamic allocation based on a percentage of memory_dynamic_max
      dynamic_min=(@property_flush[:ram].to_i*(70.0/100)).round
      Puppet.debug("mem_dyn_min is set 70% of the configured RAM = #{dynamic_min.to_s}")
      xapi.VM.set_memory_dynamic_min(@property_hash[:vm_ref], dynamic_min.to_s)
      # Give the VM the amount of ram configred
      xapi.VM.set_memory_dynamic_max(@property_hash[:vm_ref], @property_flush[:ram])

      @property_hash[:ram]=@property_flush[:ram]
      @property_hash[:memory_dynamic_mim]=dynamic_min
    end


    Puppet.debug("Stage 12")
    if @property_flush[:homeserver] &&  @property_flush[:homeserver] == "auto"
      xapi.VM.set_affinity(@property_hash[:vm_ref], 'OpaqueRef:NULL')
    end

    Puppet.debug("Stage 13")
    if @property_flush[:homeserver] &&  @property_flush[:homeserver] != "auto"
      homeserver_ref = xapi.host.get_by_name_label(@property_flush[:homeserver])
      puts homeserver_ref
      puts @property_hash[:vm_ref]
      xapi.VM.set_affinity(homeserver_ref, @property_hash[:vm_ref])
    end

  end
end
