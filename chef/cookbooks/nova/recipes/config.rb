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
  if node.platform == "suse"
    package_name "openstack-nova"
  else
    options "--force-yes -o Dpkg::Options::=\"--force-confdef\""
  end
  action :upgrade
end

include_recipe "database::client"

env_filter = " AND database_config_environment:database-config-#{node[:nova][:db][:sql_instance]}"
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

sql_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(sql, "admin").address if sql_address.nil?
Chef::Log.info("database server found at #{sql_address}")
sql_connection = "#{backend_name}://#{node[:nova][:db][:user]}:#{node[:nova][:db][:password]}@#{sql_address}/#{node[:nova][:db][:database]}"

env_filter = " AND nova_config_environment:#{node[:nova][:config][:environment]}"
rabbits = search(:node, "recipes:nova\\:\\:rabbit#{env_filter}") || []
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
api_scheme = api[:nova][:api][:protocol]
public_api_host = 'public.'+api[:fqdn]
admin_api_host = api[:fqdn]
Chef::Log.info("Api server found at #{public_api_host} #{admin_api_host}")

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
  glance_server_protocol = glance_server[:glance][:api][:protocol]
  glance_server_host = glance_server[:fqdn]
  glance_server_port = glance_server[:glance][:api][:bind_port]
else
  glance_server_protocol = 'http'
  glance_server_host = nil
  glance_server_port = nil
end
Chef::Log.info("Glance server at #{glance_server_host}")

vncproxies = search(:node, "recipes:nova\\:\\:vncproxy#{env_filter}") || []
if vncproxies.length > 0
  vncproxy = vncproxies[0]
  vncproxy = node if vncproxy.name == node.name
  vncproxy_public_host = 'public.'+vncproxy[:fqdn]
else
  vncproxy_public_host = nil
end
Chef::Log.info("VNCProxy server at #{vncproxy_public_host}")

cookbook_file "/etc/default/nova-common" do
  source "nova-common"
  owner "openstack-nova"
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

networks = search(:node, "recipes:nova\\:\\:network#{env_filter}") || []
if networks.length > 0
  network = networks[0]
  network = node if network.name == node.name
else
  network = node
end
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

if node[:nova][:volume][:type] == "rados"
  package "ceph" do
    action :upgrade
  end

  env_filter = " AND ceph_config_environment:ceph-config-#{node[:nova][:volume][:ceph_instance]}"
  ceph_monitors = []
  ceph_monitors = search(:node, "roles:ceph-mon-master*#{env_filter}") || []
  if ceph_monitors.empty? 
    Chef::Log.error("No ceph monitor found")
  end
  node[:nova][:volume][:ceph_secret_file] = "/etc/nova/nova.ceph.secret"
  node[:nova][:volume][:rbd_user] = "admin"
  node[:nova][:volume][:ceph_secret] = ceph_monitors[0]["ceph"]["secrets"]["client.admin"]

  # Don't overwrite files created by the ceph recipes
  if ( node[:roles].grep(/^ceph-/).empty? )
    ceph_keyring "client.admin" do
      secret node[:nova][:volume][:ceph_secret]
      action [:create, :add]
    end

    monitors = []
    ceph_monitors.each do |n|
      monitor = {}
      monitor[:address] = Chef::Recipe::Barclamp::Inventory.get_network_by_type(n, "admin").address
      monitor[:name] = n[:hostname]
      monitors << monitor
    end
  
    ceph_config  "ceph client config" do
      config_file   "/etc/ceph/ceph.conf"
      monitors      monitors
      clustername   node[:ceph][:clustername]
    end
  end
  # the nova user need read access to the key
  file "/etc/ceph/client.admin.keyring" do
    owner "root"
    group node[:nova][:user]
    mode "0640"
    action :touch
  end

end

# expose all apis on the controller, and only the metadata api on compute
# nodes
if node["roles"].include?("nova-multi-controller")
  enabled_apis = ['ec2','osapi_compute','osapi_volume','metadata']
else
  enabled_apis = ['metadata']
end


directory "/var/lock/nova" do
  action :create
  owner "openstack-nova"
  group "root"
end
template "/etc/nova/nova.conf" do
  source "nova.conf.erb"
  owner "openstack-nova"
  group "root"
  mode 0640
  variables(
            :sql_connection => sql_connection,
            :rabbit_settings => rabbit_settings,
            :libvirt_type => node[:nova][:libvirt_type],
            :ec2_scheme => api_scheme,
            :ec2_host => admin_api_host,
            :ec2_dmz_host => public_api_host,
            :enabled_apis => enabled_apis,
            :dns_server_public_ip => dns_server_public_ip,
            :glance_server_protocol => glance_server_protocol,
            :glance_server_host => glance_server_host,
            :glance_server_port => glance_server_port,
            :glance_ssl_no_verify => node[:nova][:glance_ssl_no_verify],
            :vncproxy_ssl_enable => node[:nova][:novnc][:ssl_enabled],
            :vncproxy_public_host => vncproxy_public_host
            )
end

template "/etc/sudoers" do
  source "sudoers.erb"
  owner "root"
  group "root"
  mode 0440
  variables( :novauser => node[:nova][:user] )
end


