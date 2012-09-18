# Copyright 2012, Dell 
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

  def proposal_dependencies(new_config)
    answer = []
    hash = new_config.config_hash
    answer << { "barclamp" => "mysql", "inst" => hash["nova"]["db"]["mysql_instance"] }
    answer << { "barclamp" => "keystone", "inst" => hash["nova"]["keystone_instance"] }
    answer << { "barclamp" => "glance", "inst" => hash["nova"]["glance_instance"] }
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

    nodes = Node.all
    nodes.delete_if { |n| n.is_admin? } if nodes.size > 1
    head = nodes.shift
    nodes = [ head ] if nodes.empty?
    add_role_to_instance_and_node(head.name, base.name, "nova-multi-controller")
    add_role_to_instance_and_node(head.name, base.name, "nova-multi-volume")
    nodes.each do |node|
      add_role_to_instance_and_node(node.name, base.name, "nova-multi-compute")
    end

    hash = base.config_hash
    # automatically swap to qemu if using VMs for testing (relies on node.virtual to detect VMs)
    nodes.each do |n|
      if n.virtual?
        hash["nova"]["libvirt_type"] = "qemu"
        break
      end
    end

    hash["nova"]["db"]["mysql_instance"] = ""
    begin
      mysql = Barclamp.find_by_name("mysql")
      mysqls = mysql.active_proposals
      if mysqls.empty?
        # No actives, look for proposals
        mysqls = mysql.proposals
      end
      hash["nova"]["db"]["mysql_instance"] = mysqls[0].name unless mysqls.empty?
    rescue
      @logger.info("Nova create_proposal: no mysql found")
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
    hash["nova"]["service_password"] = '%012d' % rand(1e12)

    hash["nova"]["glance_instance"] = ""
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

    hash["nova"]["db"]["password"] = random_password
    base.config_hash = hash

    @logger.debug("Nova create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_config, new_config, all_nodes)
    @logger.debug("Nova apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    # Handle addressing
    #
    # Make sure that the front-end pieces have public ip addreses.
    #   - if we are in HA mode, then that is all nodes.
    #
    # if tenants are enabled, we don't manage interfaces on nova-fixed.
    #
    net_svc = Barclamp.find_by_name("network").operations(@logger)

    tnodes = new_config.active_config.get_nodes_by_role("nova-multi-controller")
    tnodes = all_nodes if new_config.active_config.config_hash["nova"]["network"]["ha_enabled"]
    unless tnodes.nil? or tnodes.empty?
      tnodes.each do |n|
        net_svc.allocate_ip "default", "public", "host", n.name
      end
    end

    unless new_config.active_config.config_hash["nova"]["network"]["tenant_vlans"]
      all_nodes.each do |n|
        net_svc.enable_interface "default", "nova_fixed", n.name
      end
    end

    @logger.debug("Nova apply_role_pre_chef_call: leaving")
  end

end

