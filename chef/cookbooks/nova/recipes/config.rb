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

package "nova-common" do
  options "--force-yes -o Dpkg::Options::=\"--force-confdef\""
  action :upgrade
end

package "python-mysqldb"
env_filter = " AND mysql_config_environment:mysql-config-#{node[:nova][:db][:mysql_instance]}"
mysqls = search(:node, "roles:mysql-server#{env_filter}") || []
if mysqls.length > 0
  mysql = mysqls[0]
  mysql = node if mysql.name == node.name
else
  mysql = node
end
mysql_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(mysql, "admin").address if mysql_address.nil?
Chef::Log.info("Mysql server found at #{mysql_address}")
sql_connection = "mysql://#{node[:nova][:db][:user]}:#{node[:nova][:db][:password]}@#{mysql_address}/#{node[:nova][:db][:database]}"

env_filter = " AND nova_config_environment:#{node[:nova][:config][:environment]}"
rabbits = search(:node, "recipes:nova\\:\\:rabbit#{env_filter}") || []
if rabbits.length > 0
  rabbit = rabbits[0]
  rabbit = node if rabbit.name == node.name
else
  rabbit = node
end
rabbit_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(rabbit, "admin").address if rabbit_address.nil? or rabbit_address == "0.0.0.0"
Chef::Log.info("Rabbit server found at #{rabbit_address}")
rabbit_settings = {
  :address => rabbit_address,
  :port => rabbit[:nova][:rabbit][:port],
  :user => rabbit[:nova][:rabbit][:user],
  :password => rabbit[:nova][:rabbit][:password],
  :vhost => rabbit[:nova][:rabbit][:vhost]
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

networks = search(:node, "recipes:nova\\:\\:network#{env_filter}") || []
if networks.length > 0
  network = networks[0]
  network = node if network.name == node.name
else
  network = node
end
network_public_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(network, "public").address
Chef::Log.info("Network server found at #{network_public_ip}")

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

cookbook_file "/etc/default/nova-common" do
  source "nova-common"
  owner "root"
  group "root"
  mode 0644
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

fip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(network, "nova_fixed")
if fip
  fixed_interface = fip.interface
  fixed_interface = "#{fip.interface}.#{fip.vlan}" if fip.use_vlan
else
  fixed_interface = nil
end
pip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(network, "public")
if pip
  public_interface = pip.interface
  public_interface = "#{pip.interface}.#{pip.vlan}" if pip.use_vlan
else
  public_interface = nil
end

node[:nova][:network][:public_interface] = public_interface
if !node[:nova][:network][:dhcp_enabled]
  node[:nova][:network][:flat_network_bridge] = "br#{fixed_net["vlan"]}"
  node[:nova][:network][:flat_interface] = fixed_interface
elsif !node[:nova][:network][:tenant_vlans]
  node[:nova][:network][:flat_network_bridge] = "br#{fixed_net["vlan"]}"
  node[:nova][:network][:flat_network_dhcp_start] = fixed_net["ranges"]["dhcp"]["start"]
  node[:nova][:network][:flat_interface] = fixed_interface
else
  node[:nova][:network][:vlan_interface] = fip.interface rescue nil
  node[:nova][:network][:vlan_start] = fixed_net["vlan"]
end

template "/etc/nova/nova.conf" do
  source "nova.conf.erb"
  owner "root"
  group "root"
  mode 0644
  variables(
            :sql_connection => sql_connection,
            :rabbit_settings => rabbit_settings,
            :ec2_host => admin_api_ip,
            :ec2_dmz_host => public_api_ip,
            :network_public_ip => network_public_ip,
            :dns_server_public_ip => dns_server_public_ip,
            :glance_server_ip => glance_server_ip,
            :glance_server_port => glance_server_port
            )
end

