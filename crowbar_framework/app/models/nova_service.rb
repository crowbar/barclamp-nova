#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class NovaService < PacemakerServiceObject

  def initialize(thelogger)
    super(thelogger)
    @bc_name = "nova"
  end

# Turn off multi proposal support till it really works and people ask for it.
  def self.allow_multiple_proposals?
    false
  end

  class << self
    def role_constraints
      {
        "nova-multi-controller" => {
          "unique" => false,
          "count" => 1,
          "exclude_platform" => {
            "suse" => "12.0",
            "windows" => "/.*/"
          },
          "cluster" => true
        },
        "nova-multi-compute-hyperv" => {
          "unique" => false,
          "count" => -1,
          "platform" => {
            "windows" => "/.*/"
          }
        },
        "nova-multi-compute-kvm" => {
          "unique" => false,
          "count" => -1,
          "exclude_platform" => {
            "windows" => "/.*/"
          }
        },
        "nova-multi-compute-qemu" => {
          "unique" => false,
          "count" => -1,
          "exclude_platform" => {
            "windows" => "/.*/"
          }
        },
        "nova-multi-compute-vmware" => {
          "unique" => false,
          "count" => 1,
          "exclude_platform" => {
            "windows" => "/.*/"
          }
        },
        "nova-multi-compute-xen" => {
          "unique" => false,
          "count" => -1,
          "exclude_platform" => {
            "windows" => "/.*/"
          }
        }
      }
    end
  end

  def proposal_dependencies(role)
    answer = []
    answer << { "barclamp" => "database", "inst" => role.default_attributes["nova"]["database_instance"] }
    answer << { "barclamp" => "keystone", "inst" => role.default_attributes["nova"]["keystone_instance"] }
    answer << { "barclamp" => "glance", "inst" => role.default_attributes["nova"]["glance_instance"] }
    answer << { "barclamp" => "rabbitmq", "inst" => role.default_attributes["nova"]["rabbitmq_instance"] }
    answer << { "barclamp" => "cinder", "inst" => role.default_attributes[@bc_name]["cinder_instance"] }
    answer << { "barclamp" => "neutron", "inst" => role.default_attributes[@bc_name]["neutron_instance"] }
    if role.default_attributes[@bc_name]["use_gitrepo"]
      answer << { "barclamp" => "git", "inst" => role.default_attributes[@bc_name]["git_instance"] }
    end
    answer
  end

  def node_platform_supports_xen(node)
    node[:platform] == "suse"
  end

  def node_supports_kvm(node)
    return false if node[:cpu].nil? || node[:cpu]['0'].nil?
    node[:cpu]['0'][:flags].include?("vmx") or node[:cpu]['0'][:flags].include?("svm")
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
    nodes.delete_if { |n| n.intended_role == "storage" }

    controller  = nodes.delete nodes.detect { |n| n if n.intended_role == "controller"}
    controller ||= nodes.shift
    nodes = [ controller ] if nodes.empty?

    # restrict nodes to 'compute' roles only if compute role was defined
    if nodes.detect { |n| n if n.intended_role == "compute" }
      nodes       = nodes.select { |n| n if n.intended_role == "compute" }
    end

    hyperv = nodes.select { |n| n if n[:target_platform] =~ /^(windows-|hyperv-)/ }
    non_hyperv = nodes - hyperv
    kvm = non_hyperv.select { |n| n if node_supports_kvm(n) }
    non_kvm = non_hyperv - kvm
    xen = non_kvm.select { |n| n unless n[:block_device].include?('vda') or !node_platform_supports_xen(n) }
    qemu = non_kvm - xen

    base["deployment"]["nova"]["elements"] = {
      "nova-multi-controller" => [ controller.name ],
      "nova-multi-compute-hyperv" => hyperv.map { |x| x.name },
      "nova-multi-compute-kvm" => kvm.map { |x| x.name },
      "nova-multi-compute-qemu" => qemu.map { |x| x.name },
      "nova-multi-compute-xen" => xen.map { |x| x.name }
    }

    base["attributes"][@bc_name]["git_instance"] = find_dep_proposal("git", true)
    base["attributes"][@bc_name]["itxt_instance"] = find_dep_proposal("itxt", true)
    base["attributes"][@bc_name]["database_instance"] = find_dep_proposal("database")
    base["attributes"][@bc_name]["rabbitmq_instance"] = find_dep_proposal("rabbitmq")
    base["attributes"][@bc_name]["keystone_instance"] = find_dep_proposal("keystone")
    base["attributes"][@bc_name]["glance_instance"] = find_dep_proposal("glance")
    base["attributes"][@bc_name]["cinder_instance"] = find_dep_proposal("cinder")
    base["attributes"][@bc_name]["neutron_instance"] = find_dep_proposal("neutron")

    base["attributes"]["nova"]["service_password"] = random_password
    base["attributes"]["nova"]["db"]["password"] = random_password
    base["attributes"]["nova"]["neutron_metadata_proxy_shared_secret"] = random_password

    @logger.debug("Nova create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Nova apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    unless hyperv_available?
      role.override_attributes["nova"]["elements"]["nova-multi-compute-hyperv"] = []
    end

    controller_elements, controller_nodes, ha_enabled = role_expand_elements(role, "nova-multi-controller")

    vip_networks = ["admin", "public"]

    dirty = false
    dirty = prepare_role_for_ha_with_haproxy(role, ["nova", "ha", "enabled"], ha_enabled, controller_elements, vip_networks)
    role.save if dirty

    net_svc = NetworkService.new @logger
    # All nodes must have a public IP, even if part of a cluster; otherwise
    # the VIP can't be moved to the nodes
    controller_nodes.each do |n|
      net_svc.allocate_ip "default", "public", "host", n
    end

    allocate_virtual_ips_for_any_cluster_in_networks_and_sync_dns(controller_elements, vip_networks)

    neutron = ProposalObject.find_proposal("neutron",role.default_attributes["nova"]["neutron_instance"])

    all_nodes.each do |n|
      if neutron["attributes"]["neutron"]["networking_mode"] == "gre"
        net_svc.allocate_ip "default", "os_sdn", "host", n
      else
        net_svc.enable_interface "default", "fixed", n
        if neutron["attributes"]["neutron"]["networking_mode"] == "vlan"
          # Force "use_vlan" to false in VLAN mode (linuxbridge and ovs). We
          # need to make sure that the network recipe does NOT create the
          # VLAN interfaces (ethX.VLAN)
          node = NodeObject.find_node_by_name n
          if node.crowbar["crowbar"]["network"]["fixed"]["use_vlan"]
            @logger.info("Forcing use_vlan to false for the nova_fixed network on node #{n}")
            node.crowbar["crowbar"]["network"]["fixed"]["use_vlan"] = false
            node.save
          end
        end
      end
    end unless all_nodes.nil?

    @logger.debug("Nova apply_role_pre_chef_call: leaving")
  end

  def validate_proposal_after_save proposal
    validate_one_for_role proposal, "nova-multi-controller"

    if proposal["attributes"][@bc_name]["use_gitrepo"]
      validate_dep_proposal_is_active "git", proposal["attributes"][@bc_name]["git_instance"]
    end

    elements = proposal["deployment"]["nova"]["elements"]
    nodes = Hash.new(0)

    if proposal["attributes"][@bc_name]["use_shared_instance_storage"]
      elements["nova-multi-controller"].each do |element|
        if is_cluster? element
          validation_error("Shared storage cannot be automatically setup when a cluster has the nova-multi-controller role. Please consider using the NFS Client barclamp instead.")
          break
        end
      end unless elements["nova-multi-controller"].nil?
    end

    unless elements["nova-multi-compute-hyperv"].empty? || hyperv_available?
      validation_error("Hyper-V support is not available.")
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
    elements["nova-multi-compute-vmware"].each do |n|
        nodes[n] += 1
    end unless elements["nova-multi-compute-vmware"].nil?
    elements["nova-multi-compute-xen"].each do |n|
        nodes[n] += 1
        node = NodeObject.find_node_by_name(n)
        unless node.nil? || node_platform_supports_xen(node)
            validation_error("Platform of node #{n} (#{node[:platform]}-#{node[:platform_version]}) does not support Xen.")
        end
    end unless elements["nova-multi-compute-xen"].nil?

    nodes.each do |key,value|
        if value > 1
            validation_error("Node #{key} has been assigned to a nova-multi-compute role more than once")
        end
    end unless nodes.nil?

    super
  end

  private

  def hyperv_available?
    return File.exist?('/opt/dell/chef/cookbooks/hyperv')
  end

end
