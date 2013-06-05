#
# Cookbook Name:: nova
# Recipe:: config
#
# Copyright 2010, 2011 Opscode, Inc.
# Copyright 2011 Dell, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

node[:nova][:my_ip] = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address

unless node[:nova][:use_gitrepo]
  package "nova-common" do
    if node.platform == "suse"
      package_name "openstack-nova"
    else
      options "--force-yes -o Dpkg::Options::=\"--force-confdef\""
    end
    action :upgrade
  end
else
  pfs_and_install_deps("nova")
end

include_recipe "database::client"

env_filter = " AND database_config_environment:database-config-#{node[:nova][:db][:database_instance]}"
sqls = search(:node, "roles:database-server#{env_filter}") || []
if sqls.length > 0
  sql = sqls[0]
  sql = node if sql.name == node.name
else
  sql = node
end
backend_name = Chef::Recipe::Database::Util.get_backend_name(sql)

include_recipe "#{backend_name}::client"
include_recipe "#{backend_name}::python-client"

database_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(sql, "admin").address if database_address.nil?
Chef::Log.info("database server found at #{database_address}")
database_connection = "#{backend_name}://#{node[:nova][:db][:user]}:#{node[:nova][:db][:password]}@#{database_address}/#{node[:nova][:db][:database]}"

env_filter = " AND rabbitmq_config_environment:rabbitmq-config-#{node[:nova][:rabbitmq_instance]}"
rabbits = search(:node, "roles:rabbitmq-server#{env_filter}") || []
if rabbits.length > 0
  rabbit = rabbits[0]
  rabbit = node if rabbit.name == node.name
else
  rabbit = node
end
rabbit_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(rabbit, "admin").address 
Chef::Log.info("Rabbit server found at #{rabbit_address}")
rabbit_settings = {
  :address => rabbit_address,
  :port => rabbit[:rabbitmq][:port],
  :user => rabbit[:rabbitmq][:user],
  :password => rabbit[:rabbitmq][:password],
  :vhost => rabbit[:rabbitmq][:vhost]
}

apis = search(:node, "recipes:nova\\:\\:api#{env_filter}") || []
if apis.length > 0 and !node[:nova][:network][:ha_enabled]
  api = apis[0]
  api = node if api.name == node.name
else
  api = node
end
public_api_ip = api_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(api, "public").address
admin_api_ip = api_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(api, "admin").address
node[:nova][:api] = public_api_ip
Chef::Log.info("Api server found at #{public_api_ip} #{admin_api_ip}")

dns_servers = search(:node, "roles:dns-server") || []
if dns_servers.length > 0
  dns_server = dns_servers[0]
  dns_server = node if dns_server.name == node.name
else
  dns_server = node
end
dns_server_public_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(dns_server, "public").address
Chef::Log.info("DNS server found at #{dns_server_public_ip}")

glance_servers = search(:node, "roles:glance-server") || []
if glance_servers.length > 0
  glance_server = glance_servers[0]
  glance_server = node if glance_server.name == node.name
  glance_server_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(glance_server, "admin").address
  glance_server_port = glance_server[:glance][:api][:bind_port]
else
  glance_server_ip = nil
  glance_server_port = nil
end
Chef::Log.info("Glance server at #{glance_server_ip}")

vncproxies = search(:node, "recipes:nova\\:\\:vncproxy#{env_filter}") || []
if vncproxies.length > 0
  vncproxy = vncproxies[0]
  vncproxy = node if vncproxy.name == node.name
else
  vncproxy = node
end
vncproxy_public_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(vncproxy, "public").address
Chef::Log.info("VNCProxy server at #{vncproxy_public_ip}")

cookbook_file "/etc/default/nova-common" do
  source "nova-common"
  owner node[:nova][:user]
  group "root"
  mode 0640
  action :nothing
end

def mask_to_bits(mask)
  octets = mask.split(".")
  count = 0
  octets.each do |octet|
    break if octet == "0"
    c = 1 if octet == "128"
    c = 2 if octet == "192"
    c = 3 if octet == "224"
    c = 4 if octet == "240"
    c = 5 if octet == "248"
    c = 6 if octet == "252"
    c = 7 if octet == "254"
    c = 8 if octet == "255"
    count = count + c
  end

  count
end

# build the public_interface for the fixed net
public_net = node["network"]["networks"]["public"]
fixed_net = node["network"]["networks"]["nova_fixed"]
nova_floating = node[:network][:networks]["nova_floating"]

node[:nova][:network][:fixed_range] = "#{fixed_net["subnet"]}/#{mask_to_bits(fixed_net["netmask"])}"
node[:nova][:network][:floating_range] = "#{nova_floating["subnet"]}/#{mask_to_bits(nova_floating["netmask"])}"

fip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "nova_fixed")
if fip
  fixed_interface = fip.interface
  fixed_interface = "#{fip.interface}.#{fip.vlan}" if fip.use_vlan
else
  fixed_interface = nil
end
pip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "public")
if pip
  public_interface = pip.interface
  public_interface = "#{pip.interface}.#{pip.vlan}" if pip.use_vlan
else
  public_interface = nil
end

flat_network_bridge = fixed_net["use_vlan"] ? "br#{fixed_net["vlan"]}" : "br#{fixed_interface}"

node[:nova][:network][:public_interface] = public_interface
if !node[:nova][:network][:dhcp_enabled]
  node[:nova][:network][:flat_network_bridge] = flat_network_bridge
  node[:nova][:network][:flat_interface] = fixed_interface
elsif !node[:nova][:network][:tenant_vlans]
  node[:nova][:network][:flat_network_bridge] = flat_network_bridge
  node[:nova][:network][:flat_network_dhcp_start] = fixed_net["ranges"]["dhcp"]["start"]
  node[:nova][:network][:flat_interface] = fixed_interface
else
  node[:nova][:network][:vlan_interface] = fip.interface rescue nil
  node[:nova][:network][:vlan_start] = fixed_net["vlan"]
end

if node[:nova][:use_gitrepo]
  nova_path = "/opt/nova"
  package("libvirt-bin")
  create_user_and_dirs "nova" do
    opt_dirs ["/var/lib/nova/instances"]
    user_gid "libvirtd"
  end

  execute "cp_policy.json" do
    command "cp #{nova_path}/etc/nova/policy.json /etc/nova/"
    creates "/etc/nova/policy.json"
  end
  
  template "/etc/sudoers.d/nova-rootwrap" do
    source "nova-rootwrap.erb"
    mode 0440
    variables(:user => node[:nova][:user])
  end

  bash "deploy_filters" do
    cwd nova_path
    code <<-EOH
    ### that was copied from devstack's stack.sh
    if [[ -d $NOVA_DIR/etc/nova/rootwrap.d ]]; then
      # Wipe any existing rootwrap.d files first
      if [[ -d $NOVA_CONF_DIR/rootwrap.d ]]; then
          rm -rf $NOVA_CONF_DIR/rootwrap.d
      fi
      # Deploy filters to /etc/nova/rootwrap.d
      mkdir -m 755 $NOVA_CONF_DIR/rootwrap.d
      cp $NOVA_DIR/etc/nova/rootwrap.d/*.filters $NOVA_CONF_DIR/rootwrap.d
      chown -R root:root $NOVA_CONF_DIR/rootwrap.d
      chmod 644 $NOVA_CONF_DIR/rootwrap.d/*
      # Set up rootwrap.conf, pointing to /etc/nova/rootwrap.d
      cp $NOVA_DIR/etc/nova/rootwrap.conf $NOVA_CONF_DIR/
      sed -e "s:^filters_path=.*$:filters_path=$NOVA_CONF_DIR/rootwrap.d:" -i $NOVA_CONF_DIR/rootwrap.conf
      chown root:root $NOVA_CONF_DIR/rootwrap.conf
      chmod 0644 $NOVA_CONF_DIR/rootwrap.conf
    fi
    ### end
  EOH
  environment({
    'NOVA_DIR' => nova_path,
    'NOVA_CONF_DIR' => '/etc/nova',
  })
  not_if {File.exists?("/etc/nova/rootwrap.d")}
  end
end

if node.recipes.include?("nova::volume") and node[:nova][:volume][:volume_type] == "eqlx"
  Chef::Log.info("Pushing EQLX params to nova.conf template")
  eqlx_params = node[:nova][:volume][:eqlx]
else
  eqlx_params = nil
end


env_filter = " AND keystone_config_environment:keystone-config-#{node[:nova][:keystone_instance]}"
keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
if keystones.length > 0
  keystone = keystones[0]
  keystone = node if keystone.name == node.name
else
  keystone = node
end

keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
keystone_token = keystone["keystone"]["service"]["token"]
keystone_service_port = keystone["keystone"]["api"]["service_port"]
keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
keystone_service_user = node[:nova][:service_user]
keystone_service_password = node[:nova][:service_password]
Chef::Log.info("Keystone server found at #{keystone_address}")



quantum_servers = search(:node, "roles:quantum-server") || []
if quantum_servers.length > 0
  quantum_server = quantum_servers[0]
  quantum_server = node if quantum_server.name == node.name
  quantum_server_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(quantum_server, "admin").address
  quantum_server_port = quantum_server[:quantum][:api][:service_port]
  quantum_service_user = quantum_server[:quantum][:service_user]
  quantum_service_password = quantum_server[:quantum][:service_password]
  if quantum_server[:quantum][:networking_mode] != 'local'
    per_tenant_vlan=true
  else
    per_tenant_vlan=false
  end
  quantum_networking_mode = quantum_server[:quantum][:networking_mode]
else
  quantum_server_ip = nil
  quantum_server_port = nil
  quantum_service_user = nil
  quantum_service_password = nil
end
Chef::Log.info("Quantum server at #{quantum_server_ip}")

template "/etc/nova/nova.conf" do
  source "nova.conf.erb"
  owner node[:nova][:user]
  group "root"
  mode 0640
  variables(
            :dhcpbridge => "#{node[:nova][:use_gitrepo] ? nova_path:"/usr"}/bin/nova-dhcpbridge",
            :database_connection => database_connection,
            :rabbit_settings => rabbit_settings,
            :ec2_host => admin_api_ip,
            :ec2_dmz_host => public_api_ip,
            :dns_server_public_ip => dns_server_public_ip,
            :glance_server_ip => glance_server_ip,
            :glance_server_port => glance_server_port,
            :vncproxy_public_ip => vncproxy_public_ip,
            :eqlx_params => eqlx_params,
            :quantum_server_ip => quantum_server_ip,
            :quantum_server_port => quantum_server_port,
            :quantum_service_user => quantum_service_user,
            :quantum_service_password => quantum_service_password,
            :keystone_service_tenant => keystone_service_tenant,
            :keystone_address => keystone_address,
            :keystone_admin_port => keystone_admin_port
            )
end

