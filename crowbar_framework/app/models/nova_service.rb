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
    sql_engine = role.default_attributes["nova"]["db"]["sql_engine"]
    answer << { "barclamp" => sql_engine, "inst" => role.default_attributes["nova"]["db"]["sql_instance"] }
    answer << { "barclamp" => "keystone", "inst" => role.default_attributes["nova"]["keystone_instance"] }
    answer << { "barclamp" => "glance", "inst" => role.default_attributes["nova"]["glance_instance"] }
    answer
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
    nodes.delete_if { |n| n.nil? or n.admin? }
    head = nodes.shift
    nodes = [ head ] if nodes.empty?
    base["deployment"]["nova"]["elements"] = {
      "nova-multi-controller" => [ head.name ],
      "nova-multi-compute" => nodes.map { |x| x.name }
    }

    base["attributes"]["nova"]["db"]["sql_engine"] = ""
    base["attributes"]["nova"]["db"]["sql_instance"] = ""
    begin
      mysqlService = MysqlService.new(@logger)
      mysqls = mysqlService.list_active[1]
      if mysqls.empty?
        # No actives, look for proposals
        mysqls = mysqlService.proposals[1]
      end
      if mysqls.empty?
        @logger.info("Nova create_proposal: no mysql proposal found")
        base["attributes"]["nova"]["db"]["sql_engine"] = ""
      else
        base["attributes"]["nova"]["db"]["sql_instance"] = mysqls[0]
        base["attributes"]["nova"]["db"]["sql_engine"] = "mysql"
      end
    rescue
      @logger.info("Nova create_proposal: no mysql found")
    end
    if base["attributes"]["nova"]["db"]["sql_engine"] == ""
      begin
        pgsqlService = PostgresqlService.new(@logger)
        # Look for active roles
        pgsqls = pgsqlService.list_active[1]
        if pgsqls.empty?
          @logger.info("Nova create_proposal: no active postgresql proposal found")
          # No actives, look for proposals
          pgsqls = pgsqlService.proposals[1]
        end
        if pgsqls.empty?
          @logger.info("Nova create_proposal: no postgressql proposal found")
          base["attributes"]["nova"]["db"]["sql_engine"] = ""
        else
          @logger.info("Nova create_proposal: postgresql instance #{pgsqls[0]}")
          base["attributes"]["nova"]["db"]["sql_instance"] = pgsqls[0]
          base["attributes"]["nova"]["db"]["sql_engine"] = "postgresql"
        end
      rescue
        @logger.info("Keystone create_proposal: no postgresql found")
        base["attributes"]["keystone"]["sql_engine"] = ""
      end
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

    @logger.debug("Nova apply_role_pre_chef_call: leaving")
  end

end

