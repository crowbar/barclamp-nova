# Copyright 2013, Dell 
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#  http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License. 
# 

class BarclampNova::Barclamp < Barclamp

  def initialize(thelogger)
    @bc_name = "nova"
    @logger = thelogger
  end

# Turn off multi proposal support till it really works and people ask for it.
  def self.allow_multiple_proposals?
    false
  end

  def proposal_dependencies(role)
    answer = []
    answer << { "barclamp" => "database", "inst" => role.default_attributes["nova"]["database_instance"] }
    answer << { "barclamp" => "keystone", "inst" => role.default_attributes["nova"]["keystone_instance"] }
    answer << { "barclamp" => "glance", "inst" => role.default_attributes["nova"]["glance_instance"] }
    answer << { "barclamp" => "rabbitmq", "inst" => role.default_attributes["nova"]["rabbitmq_instance"] }
    answer << { "barclamp" => "cinder", "inst" => role.default_attributes[@bc_name]["cinder_instance"] }
    if role.default_attributes[@bc_name]["use_gitrepo"]
      answer << { "barclamp" => "git", "inst" => role.default_attributes[@bc_name]["git_instance"] }
    end

    if role.default_attributes[@bc_name]["networking_backend"] == "neutron"
      answer << { "barclamp" => "neutron", "inst" => role.default_attributes[@bc_name]["neutron_instance"] }
    end
    answer
  end

  #
  # Lots of enhancements here.  Like:
  #    * Don't reuse machines
  #    * validate hardware.
  #
  def create_proposal(name)
    @logger.debug("Nova create_proposal: entering")
    base = super(name)
    @logger.debug("Nova create_proposal: done with base")

    nodes = Node.all
    nodes.delete_if { |n| n.is_admin? } if nodes.size > 1
    head = nodes.shift
    nodes = [ head ] if nodes.empty?

    hyperv = nodes.select { |n| n if n[:target_platform] =~ /^(windows-|hyperv-)/ }
    non_hyperv = nodes - hyperv
    kvm = non_hyperv.select { |n| n if n[:cpu]['0'][:flags].include?("vmx") or n[:cpu]['0'][:flags].include?("svm") }
    qemu = non_hyperv - kvm

    base["deployment"]["nova"]["elements"] = {
      "nova-multi-controller" => [ head.name ],
      "nova-multi-compute-hyperv" => hyperv.map { |x| x.name },
      "nova-multi-compute-kvm" => kvm.map { |x| x.name },
      "nova-multi-compute-qemu" => qemu.map { |x| x.name }  
    }

    base["attributes"][@bc_name]["git_instance"] = ""
    begin
      gitService = GitService.new(@logger)
      gits = gitService.list_active[1]
      if gits.empty?
        # No actives, look for proposals
        gits = gitService.proposals[1]
      end
      unless gits.empty?
        base["attributes"][@bc_name]["git_instance"] = gits[0]
      end
    rescue
      @logger.info("#{@bc_name} create_proposal: no git found")
    end

    base["attributes"]["nova"]["database_instance"] = ""
    begin
      databaseService = DatabaseService.new(@logger)
      dbs = databaseService.list_active[1]
      if dbs.empty?
        # No actives, look for proposals
        dbs = databaseService.proposals[1]
      end
      if dbs.empty?
        @logger.info("Nova create_proposal: no database proposal found")
      else
        base["attributes"]["nova"]["database_instance"] = dbs[0]
      end
    rescue
      @logger.info("Nova create_proposal: no database found")
    end

    if base["attributes"]["nova"]["database_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "database"))
    end

    base["attributes"]["nova"]["rabbitmq_instance"] = ""
    begin
      rabbitmqService = RabbitmqService.new(@logger)
      rabbitmqs = rabbitmqService.list_active[1]
      if rabbitmqs.empty?
        # No actives, look for proposals
        rabbitmqs = rabbitmqService.proposals[1]
      end
      base["attributes"]["nova"]["rabbitmq_instance"] = rabbitmqs[0] unless rabbitmqs.empty?
    rescue
      @logger.info("Nova create_proposal: no rabbitmq found")
    end

    if base["attributes"]["nova"]["rabbitmq_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "rabbitmq"))
    end

    hash["nova"]["keystone_instance"] = ""
    begin
      keystoneService = Barclamp.find_by_name("keystone")
      keystones = keystoneService.active_proposals
      if keystones.empty?
        # No actives, look for proposals
        keystones = keystoneService.proposals
      end
      hash["nova"]["keystone_instance"] = keystones[0].name unless keystones.empty?
    rescue
      @logger.info("Nova create_proposal: no keystone found")
    end

    if base["attributes"]["nova"]["keystone_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "keystone"))
    end

    base["attributes"]["nova"]["service_password"] = '%012d' % rand(1e12)

    base["attributes"][@bc_name]["itxt_instance"] = ""
    begin
      itxtService = InteltxtService.new(@logger)
      itxts = itxtService.list_active[1]
      if itxts.empty?
        # No actives, look for proposals
        #itxts = itxtService.proposals[1]
        itxts = [ "None" ]
      end
      unless itxts.empty?
        base["attributes"][@bc_name]["itxt_instance"] = itxts[0]
      end
    rescue
      @logger.info("#{@bc_name} create_proposal: no itxt found")
    end

    base["attributes"]["nova"]["glance_instance"] = ""
    begin
      glanceService = Barclamp.find_by_name("glance")
      glances = glanceService.active_proposals
      if glances.empty?
        # No actives, look for proposals
        glances = glanceService.proposals
      end
      hash["nova"]["glance_instance"] = glances[0].name unless glances.empty?
    rescue
      @logger.info("Nova create_proposal: no glance found")
    end

    if base["attributes"]["nova"]["glance_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "glance"))
    end

    base["attributes"]["nova"]["cinder_instance"] = ""
    begin
      cinderService = CinderService.new(@logger)
      cinders = cinderService.list_active[1]
      if cinders.empty?
        # No actives, look for proposals
        cinders = cinderService.proposals[1]
      end
      base["attributes"]["nova"]["cinder_instance"] = cinders[0] unless cinders.empty?
    rescue
      @logger.info("Nova create_proposal: no cinder found")
    end

    if base["attributes"]["nova"]["cinder_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "cinder"))
    end

    base["attributes"]["nova"]["neutron_instance"] = ""
    begin
      neutronService = NeutronService.new(@logger)
      neutrons = neutronService.list_active[1]
      if neutrons.empty?
        # No actives, look for proposals
        neutrons = neutronService.proposals[1]
      end
      base["attributes"]["nova"]["neutron_instance"] = neutrons[0] unless neutrons.empty?
    rescue
      @logger.info("Nova create_proposal: no neutron found")
    end

    if base["attributes"]["nova"]["neutron_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "neutron"))
    end

    base["attributes"]["nova"]["db"]["password"] = random_password
    base["attributes"]["nova"]["neutron_metadata_proxy_shared_secret"] = random_password

    @logger.debug("Nova create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_config, new_config, all_nodes)
    @logger.debug("Nova apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    unless hyperv_available?
      role.override_attributes["nova"]["elements"]["nova-multi-compute-hyperv"] = []
    end

    # Handle addressing
    #
    # Make sure that the front-end pieces have public ip addreses.
    #   - if we are in HA mode, then that is all nodes.
    #
    # if tenants are enabled, we don't manage interfaces on nova-fixed.
    #
    net_svc = NetworkService.new @logger
    tnodes = role.override_attributes["nova"]["elements"]["nova-multi-controller"]
    if role.default_attributes["nova"]["networking_backend"]=="neutron"
      tnodes.each do |n|
        net_svc.allocate_ip "default","public","host",n
      end unless tnodes.nil?
      neutron = ProposalObject.find_proposal("neutron",role.default_attributes["nova"]["neutron_instance"])
      all_nodes.each do |n|
        if neutron["attributes"]["neutron"]["networking_mode"] == "gre"
          net_svc.allocate_ip "default", "os_sdn", "host", n
        else
          net_svc.enable_interface "default", "nova_fixed", n
          if neutron["attributes"]["neutron"]["networking_mode"] == "vlan"
            # Force "use_vlan" to false in VLAN mode (linuxbridge and ovs). We
            # need to make sure that the network recipe does NOT create the
            # VLAN interfaces (ethX.VLAN)
            node = NodeObject.find_node_by_name n
            if node.crowbar["crowbar"]["network"]["nova_fixed"]["use_vlan"]
              @logger.info("Forcing use_vlan to false for the nova_fixed network on node #{n}")
              node.crowbar["crowbar"]["network"]["nova_fixed"]["use_vlan"] = false
              node.save
            end
          end
        end
      end unless all_nodes.nil?
    else
      tnodes = all_nodes if role.default_attributes["nova"]["network"]["ha_enabled"]
      unless tnodes.nil? or tnodes.empty?
        tnodes.each do |n|
          net_svc.allocate_ip "default", "public", "host", n
          unless role.default_attributes["nova"]["network"]["tenant_vlans"]
            net_svc.allocate_ip "default", "nova_fixed", "router", n
          end
        end
      end
      unless role.default_attributes["nova"]["network"]["tenant_vlans"]
        all_nodes.each do |n|
          net_svc.enable_interface "default", "nova_fixed", n
        end
      end
    end
    @logger.debug("Nova apply_role_pre_chef_call: leaving")
  end

  def validate_proposal_after_save proposal
    super

    if proposal["attributes"][@bc_name]["use_gitrepo"]
      gitService = GitService.new(@logger)
      gits = gitService.list_active[1].to_a
      if not gits.include?proposal["attributes"][@bc_name]["git_instance"]
        raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "git"))
      end
    end

    errors = []
    elements = proposal["deployment"]["nova"]["elements"]
    nodes = Hash.new(0)

    unless elements["nova-multi-compute-hyperv"].empty? || hyperv_available?
      errors << "Hyper-V support is not available."
    end

    elements["nova-multi-compute-hyperv"].each do |n|
        nodes[n] += 1
    end unless elements["nova-multi-compute-hyperv"].nil?
    elements["nova-multi-compute-kvm"].each do |n|
        nodes[n] += 1
    end unless elements["nova-multi-compute-kvm"].nil?
    elements["nova-multi-compute-qemu"].each do |n|
        nodes[n] += 1
    end unless elements["nova-multi-compute-qemu"].nil?

    nodes.each do |key,value|
        if value > 1
            errors << "Node #{key} has been already assigned to nova-multi-compute role twice"
        end
    end unless nodes.nil?

    if errors.length > 0
      raise Chef::Exceptions::ValidationFailed.new(errors.join("\n"))
    end

  end

  private

  def hyperv_available?
    return File.exist?('/opt/dell/chef/cookbooks/hyperv')
  end

end
