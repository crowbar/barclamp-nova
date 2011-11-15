#
# Cookbook Name:: nova
# Recipe:: api
#
# Copyright 2010, Opscode, Inc.
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

include_recipe "nova::config"

package "python-keystone" do
  action :install
end

nova_package("api")

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
Chef::Log.info("Keystone server found at #{keystone_address}")

template "/etc/nova/api-paste.ini" do
  source "api-paste.ini.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :keystone_ip_address => keystone_address,
    :keystone_admin_token => keystone_token
  )
  notifies :restart, resources(:service => "nova-api"), :immediately
end

my_ipaddress = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address


keystone_register "register nova service" do
  host keystone_address
  token keystone_token
  service_name "nova"
  service_description "Openstack Nova Service"
  action :add_service
end

keystone_register "register nova compat service" do
  host keystone_address
  token keystone_token
  service_name "nova_compat"
  service_description "Openstack Nova Compat Service"
  action :add_service
end

keystone_register "register nova_compat endpoint" do
  host keystone_address
  token keystone_token
  endpoint_service "nova_compat"
  endpoint_region "RegionOne"
  endpoint_adminURL "http://#{my_ipaddress}:8774/v1.0"
  endpoint_internalURL "http://#{my_ipaddress}:8774/v1.0"
  endpoint_publicURL "http://#{my_ipaddress}:8774/v1.0"
#  endpoint_global true
#  endpoint_enabled true
  action :add_endpoint_template
end

keystone_register "register nova endpoint" do
  host keystone_address
  token keystone_token
  endpoint_service "nova"
  endpoint_region "RegionOne"
  endpoint_adminURL "http://#{my_ipaddress}:8774/v1.1/%tenant_id%"
  endpoint_internalURL "http://#{my_ipaddress}:8774/v1.1/%tenant_id%"
  endpoint_publicURL "http://#{my_ipaddress}:8774/v1.1/%tenant_id%"
#  endpoint_global true
#  endpoint_enabled true
  action :add_endpoint_template
end

