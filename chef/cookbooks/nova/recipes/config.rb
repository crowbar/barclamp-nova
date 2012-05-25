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

package "nova-common" do
  options "--force-yes -o Dpkg::Options::=\"--force-confdef\""
  action :upgrade
end

mysql_env = "AND mysql_config_environment:mysql-config-#{node[:nova][:db][:mysql_instance]}"
nova_env = "AND nova_config_environment:#{node[:nova][:config][:environment]}"
package "python-mysqldb"
_r = {}
{
  :mysql => "roles:mysql-server #{mysql_env}",
  :rabbit => "recipes:nova\\:\\:rabbit #{nova_env}",
  :api  => "recipes:nova\\:\\:api #{nova_env}",
  :network  => "recipes:nova\\:\\:network #{nova_env}",
  :vncproxy  => "recipes:nova\\:\\:vncproxy #{nova_env}",
  :dns  => "roles:dns-server",
  :glance  => "roles:glance-server"
}.each{|role,query|
  if n = search(:node, query)[0]
    Chef::Log.info("Found node #{n[:fqdn]} with role #{role.to_s}")
  else
    Chef::Log.info("Could not find node for #{role}, using myself instead")
  end
  _r[role] = n || node
}

public_api_ip = api_ip = _r[:api].address("public").addr
admin_api_ip = api_ip =  _r[:api].address.addr
network_public_ip =      _r[:network].address("public").addr
dns_server_public_ip =   _r[:dns].address("public").addr
glance_server_ip =       _r[:glance].address.addr
glance_server_port =     _r[:glance][:glance][:api][:bind_port]
vncproxy_public_ip =     _r[:vncproxy].address("public").addr

node[:nova][:my_ip] = node.address.addr

sql_connection = "mysql://#{node[:nova][:db][:user]}:#{node[:nova][:db][:password]}@#{_r[:mysql].address.addr}/#{node[:nova][:db][:database]}"

rabbit_settings = {
  :address => _r[:rabbit].address.addr,
  :port => _r[:rabbit][:nova][:rabbit][:port],
  :user => _r[:rabbit][:nova][:rabbit][:user],
  :password => _r[:rabbit][:nova][:rabbit][:password],
  :vhost => _r[:rabbit][:nova][:rabbit][:vhost]
}
node[:nova][:api] = public_api_ip

cookbook_file "/etc/default/nova-common" do
  source "nova-common"
  owner "nova"
  group "root"
  mode 0640
  action :nothing
end

# build the public_interface for the fixed net
public_net = node["network"]["networks"]["public"]
fixed_net = node["network"]["networks"]["nova_fixed"]
nova_floating = node[:network][:networks]["nova_floating"]

node[:nova][:network][:fixed_range] = IP.coerce("#{fixed_net["subnet"]}/#{fixed_net["netmask"]}").network.to_s
node[:nova][:network][:floating_range] = IP.coerce("#{nova_floating["subnet"]}/#{nova_floating["netmask"]}").network.to_s
node[:nova][:network][:public_interface] = _r[:network].interface("public").name

fixed_interface = _r[:network].interface("nova_fixed").name
public_interface = _r[:network].interface("public").name

if !node[:nova][:network][:dhcp_enabled]
  node[:nova][:network][:flat_network_bridge] = fixed_interface
elsif !node[:nova][:network][:tenant_vlans]
  node[:nova][:network][:flat_network_bridge] = fixed_interface
  node[:nova][:network][:flat_network_dhcp_start] = fixed_net["ranges"]["dhcp"]["start"]
else
  node[:nova][:network][:vlan_interface] = fixed_interface
  node[:nova][:network][:vlan_start] = fixed_net["vlan"]
end

template "/etc/nova/nova.conf" do
  source "nova.conf.erb"
  owner "nova"
  group "root"
  mode 0640
  variables(
            :sql_connection => sql_connection,
            :rabbit_settings => rabbit_settings,
            :ec2_host => admin_api_ip,
            :ec2_dmz_host => public_api_ip,
            :network_public_ip => network_public_ip,
            :dns_server_public_ip => dns_server_public_ip,
            :glance_server_ip => glance_server_ip,
            :glance_server_port => glance_server_port,
            :vncproxy_public_ip => vncproxy_public_ip
            )
end

