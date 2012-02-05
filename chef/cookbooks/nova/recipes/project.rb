#
# Cookbook Name:: nova
# Recipe:: setup
#
# Copyright 2010-2011, Opscode, Inc.
# Copyright 2011, Anso Labs
# Copyright 2011, Dell, Inc.
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

include_recipe "nova::mysql"
include_recipe "nova::config"

execute "nova-manage db sync" do
  command "nova-manage db sync"
  action :run
end

# ha_enabled activates Nova High Availability (HA) networking.
# The nova "network" and "api" recipes need to be included on the compute nodes and
# we must specify the --multi_host=T switch on "nova-manage network create". 
cmd = "nova-manage network create --fixed_range_v4=#{node[:nova][:network][:fixed_range]} --num_networks=#{node[:nova][:network][:num_networks]} --network_size=#{node[:nova][:network][:network_size]} --label nova_fixed" 
cmd << " --multi_host=T" if node[:nova][:network][:ha_enabled]
execute cmd do
  user node[:nova][:user]
  not_if "nova-manage network list | grep '#{node[:nova][:network][:fixed_range].split("/")[0]}'"
end

# Add private network one day.

execute "nova-manage floating create --ip_range=#{node[:nova][:network][:floating_range]}" do
  user node[:nova][:user]
  not_if "nova-manage floating list | grep '#{node[:nova][:network][:floating_range].split("/")[0]}'"
end

unless node[:nova][:network][:tenant_vlans]
  env_filter = " AND mysql_config_environment:mysql-config-#{node[:nova][:db][:mysql_instance]}"
  db_server = search(:node, "roles:mysql-server#{env_filter}")[0]
  db_server = node if db_server.name == node.name
  execute "mysql-fix-ranges-fixed" do
    command "/usr/bin/mysql -u #{node[:nova][:db][:user]} -h #{db_server[:mysql][:api_bind_host]} -p#{node[:nova][:db][:password]} #{node[:nova][:db][:database]} < /etc/mysql/nova-fixed-range.sql"
    action :nothing
  end

  fixed_net = node[:network][:networks]["nova_fixed"]
  rangeH = fixed_net["ranges"]["dhcp"]
  netmask = fixed_net["netmask"]
  subnet = fixed_net["subnet"]

  index = IPAddr.new(rangeH["start"]) & ~IPAddr.new(netmask)
  index = index.to_i
  stop_address = IPAddr.new(rangeH["end"]) & ~IPAddr.new(netmask)
  stop_address = IPAddr.new(subnet) | (stop_address.to_i + 1)
  address = IPAddr.new(subnet) | index

  network_list = []
  while address != stop_address
    network_list << address.to_s
    index = index + 1
    address = IPAddr.new(subnet) | index
  end
  network_list << address.to_s

  template "/etc/mysql/nova-fixed-range.sql" do
    path "/etc/mysql/nova-fixed-range.sql"
    source "fixed-range.sql.erb"
    owner "root"
    group "root"
    mode "0600"
    variables(
      :network => network_list
    )
    notifies :run, resources(:execute => "mysql-fix-ranges-fixed"), :immediately
  end
end

# Setup administrator credentials file
env_filter = " AND keystone_config_environment:keystone-config-#{node[:nova][:keystone_instance]}"
keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
if keystones.length > 0
  keystone = keystones[0]
  keystone = node if keystone.name == node.name
else
  keystone = node
end

keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
keystone_token = keystone["keystone"]["admin"]["token"] rescue nil
admin_username = keystone["keystone"]["admin"]["username"] rescue nil
admin_password = keystone["keystone"]["admin"]["password"] rescue nil
default_tenant = keystone["keystone"]["default"]["tenant"] rescue nil
keystone_service_port = keystone["keystone"]["api"]["service_port"] rescue nil
Chef::Log.info("Keystone server found at #{keystone_address}")

apis = search(:node, "recipes:nova\\:\\:api#{env_filter}") || []
if apis.length > 0 and !node[:nova][:network][:ha_enabled]
  api = apis[0]
  api = node if api.name == node.name
else
  api = node
end
admin_api_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(api, "admin").address
Chef::Log.info("Admin API server found at #{admin_api_ip}")

template "/root/.openrc" do
  source "openrc.erb"
  owner "root"
  group "root"
  mode 0600
  variables(
    :keystone_ip_address => keystone_address,
    :keystone_service_port => keystone_service_port,
    :admin_username => admin_username,
    :admin_password => admin_password,
    :default_tenant => default_tenant,
    :nova_api_ip_address => admin_api_ip
  )
end

