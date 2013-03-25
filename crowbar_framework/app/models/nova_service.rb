# Copyright 2011, Dell 
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

class NovaService < ServiceObject

  def initialize(thelogger)
    @bc_name = "nova"
    @logger = thelogger
  end

  def self.allow_multiple_proposals?
    true
  end

  def proposal_dependencies(role)
    answer = []
    answer << { "barclamp" => "mysql", "inst" => role.default_attributes["nova"]["db"]["mysql_instance"] }
    answer << { "barclamp" => "keystone", "inst" => role.default_attributes["nova"]["keystone_instance"] }
    answer << { "barclamp" => "glance", "inst" => role.default_attributes["nova"]["glance_instance"] }
    answer << { "barclamp" => "rabbitmq", "inst" => role.default_attributes["nova"]["rabbitmq_instance"] }
    if role.default_attributes[@bc_name]["use_gitrepo"]
      answer << { "barclamp" => "git", "inst" => role.default_attributes[@bc_name]["git_instance"] }
    end
    if role.default_attributes[@bc_name]["volume"]["use_cinder"]
      answer << { "barclamp" => "cinder", "inst" => role.default_attributes[@bc_name]["cinder_instance"] }
    end
    answer
  end


  #
  # This can be overridden to get better validation if needed.
  #
  def validate_proposal proposal
    super proposal

    val = proposal["attributes"]["nova"]["volume"]["local_size"] rescue -1
    raise I18n.t('barclamp.nova.edit_attributes.volume_file_size_error') if val < 2
  end

  #
  # Lots of enhancements here.  Like:
  #    * Don't reuse machines
  #    * validate hardware.
  #
  def create_proposal
    @logger.debug("Nova create_proposal: entering")
    base = super
    @logger.debug("Nova create_proposal: done with base")

    nodes = NodeObject.all
    nodes.delete_if { |n| n.nil? }
    nodes.delete_if { |n| n.admin? } if nodes.size > 1
    head = nodes.shift
    nodes = [ head ] if nodes.empty?
    base["deployment"]["nova"]["elements"] = {
      "nova-multi-controller" => [ head.name ],
      "nova-multi-volume" => [ head.name ],
      "nova-multi-compute" => nodes.map { |x| x.name }
    }
    # automatically swap to qemu if using VMs for testing (relies on node.virtual to detect VMs)
    nodes.each do |n|
      if n.virtual?
        base["attributes"]["nova"]["libvirt_type"] = "qemu"
        break
      end
    end

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

    base["attributes"]["nova"]["db"]["mysql_instance"] = ""
    begin
      mysqlService = MysqlService.new(@logger)
      mysqls = mysqlService.list_active[1]
      if mysqls.empty?
        # No actives, look for proposals
        mysqls = mysqlService.proposals[1]
      end
      base["attributes"]["nova"]["db"]["mysql_instance"] = mysqls[0] unless mysqls.empty?
    rescue
      @logger.info("Nova create_proposal: no mysql found")
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

    base["attributes"]["nova"]["keystone_instance"] = ""
    begin
      keystoneService = KeystoneService.new(@logger)
      keystones = keystoneService.list_active[1]
      if keystones.empty?
        # No actives, look for proposals
        keystones = keystoneService.proposals[1]
      end
      base["attributes"]["nova"]["keystone_instance"] = keystones[0] unless keystones.empty?
    rescue
      @logger.info("Nova create_proposal: no keystone found")
    end
    base["attributes"]["nova"]["service_password"] = '%012d' % rand(1e12)

    base["attributes"]["nova"]["glance_instance"] = ""
    begin
      glanceService = GlanceService.new(@logger)
      glances = glanceService.list_active[1]
      if glances.empty?
        # No actives, look for proposals
        glances = glanceService.proposals[1]
      end
      base["attributes"]["nova"]["glance_instance"] = glances[0] unless glances.empty?
    rescue
      @logger.info("Nova create_proposal: no glance found")
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

    base["attributes"]["nova"]["db"]["password"] = random_password

    @logger.debug("Nova create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Nova apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    # Handle addressing
    #
    # Make sure that the front-end pieces have public ip addreses.
    #   - if we are in HA mode, then that is all nodes.
    #
    # if tenants are enabled, we don't manage interfaces on nova-fixed.
    #
    net_svc = NetworkService.new @logger

    tnodes = role.override_attributes["nova"]["elements"]["nova-multi-controller"]
    tnodes = all_nodes if role.default_attributes["nova"]["network"]["ha_enabled"]
    unless tnodes.nil? or tnodes.empty?
      tnodes.each do |n|
        if role.default_attributes["nova"]["networking_backend"]=="nova-network"
          net_svc.allocate_ip "default", "public", "host", n
          unless role.default_attributes["nova"]["network"]["tenant_vlans"] # or role.default_attributes["nova"]["networking_backend"]=="quantum"
            net_svc.allocate_ip "default", "nova_fixed", "router", n
          end
        end
        if role.default_attributes["nova"]["networking_backend"]=="quantum"
          net_svc.enable_interface "default", "nova_fixed", n
          net_svc.allocate_ip "default", "public", "host", n
        end
      end
    end

    unless role.default_attributes["nova"]["network"]["tenant_vlans"] or role.default_attributes["nova"]["networking_backend"]=="quantum"
      all_nodes.each do |n|
        net_svc.enable_interface "default", "nova_fixed", n
      end
    end

    @logger.debug("Nova apply_role_pre_chef_call: leaving")
  end

end

