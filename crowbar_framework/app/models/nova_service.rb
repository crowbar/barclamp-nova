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

  def random_password(size = 12)
    chars = (('a'..'z').to_a + ('0'..'9').to_a) - %w(i o 0 1 l 0)
    (1..size).collect{|a| chars[rand(chars.size)] }.join
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
    if nodes.size == 1
      base["deployment"]["nova"]["elements"] = {
        "nova-single-node" => [ nodes.first[:fqdn] ]
      }
    elsif nodes.size > 1
      head = nodes.shift
      base["deployment"]["nova"]["elements"] = {
        "nova-multi-controller" => [ head.name ],
        "nova-multi-compute" => nodes.map { |x| x.name }
      }
    end

    base["attributes"]["nova"]["mysql_instance"] = ""
    begin
      mysqlService = MysqlService.new(@logger)
      mysqls = mysqlService.list_active[1]
      base["attributes"]["nova"]["mysql_instance"] = mysqls[0] unless mysqls.empty?
    rescue
      @logger.info("Nova create_proposal: no mysql found")
    end

    base["attributes"]["nova"]["keystone_instance"] = ""
    begin
      keystoneService = KeystoneService.new(@logger)
      keystones = keystoneService.list_active[1]
      base["attributes"]["nova"]["keystone_instance"] = keystones[0] unless keystones.empty?
    rescue
      @logger.info("Nova create_proposal: no keystone found")
    end

    base["attributes"]["nova"]["glance_instance"] = ""
    begin
      glanceService = GlanceService.new(@logger)
      glances = glanceService.list_active[1]
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

    # Make sure that the front-end pieces have public ip addreses.
    net_svc = NetworkService.new @logger
    [ "nova-cloud-controller", "nova-multi-controller", "nova-head", "nova-single-machine" ].each do |element|
      tnodes = role.override_attributes["nova"]["elements"][element]
      next if tnodes.nil? or tnodes.empty?
      tnodes.each do |n|
        net_svc.allocate_ip "default", "public", "host", n
        if role.default_attributes["nova"]["network_type"] != "dhcpvlan"
          net_svc.allocate_ip "default", "nova_fixed", "router", n
        end
      end
    end

    all_nodes.each do |n|
      net_svc.enable_interface "default", "nova_fixed", n
    end
    @logger.debug("Nova apply_role_pre_chef_call: leaving")
  end

end

