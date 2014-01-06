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

nova_path = "/opt/nova"
venv_path = node[:nova][:use_virtualenv] ? "#{nova_path}/.venv" : nil

keystones = search_env_filtered(:node, "recipes:keystone\\:\\:server")
if keystones.length > 0
  keystone = keystones[0]
  keystone = node if keystone.name == node.name
else
  keystone = node
end

unless node[:nova][:use_gitrepo]
  package "python-novaclient"
end

nova_package("api")
nova_package("objectstore")

keystone_host = keystone[:fqdn]
keystone_protocol = keystone["keystone"]["api"]["protocol"]
keystone_token = keystone["keystone"]["service"]["token"]
keystone_service_port = keystone["keystone"]["api"]["service_port"]
keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
keystone_service_user = node["nova"]["service_user"]
keystone_service_password = node["nova"]["service_password"]
Chef::Log.info("Keystone server found at #{keystone_host}")

directory "/var/cache/nova" do
  owner node[:nova][:user]
  group node[:nova][:group]
end

template "/etc/nova/api-paste.ini" do
  source "api-paste.ini.erb"
  owner node[:nova][:user]
  group "root"
  mode "0640"
  variables(
    :keystone_protocol => keystone_protocol,
    :keystone_host => keystone_host,
    :keystone_admin_token => keystone_token,
    :keystone_service_port => keystone_service_port,
    :keystone_service_tenant => keystone_service_tenant,
    :keystone_service_user => keystone_service_user,
    :keystone_service_password => keystone_service_password,
    :keystone_admin_port => keystone_admin_port
  )
  notifies :restart, resources(:service => "nova-api"), :immediately
end

apis = search_env_filtered(:node, "recipes:nova\\:\\:api")
if apis.length > 0 and !node[:nova][:network][:ha_enabled]
  api = apis[0]
  api = node if api.name == node.name
else
  api = node
end
admin_api_host = api[:fqdn]
# For the public endpoint, we prefer the public name. If not set, then we
# use the IP address except for SSL, where we always prefer a hostname
# (for certificate validation).
public_api_host = api[:crowbar][:public_name]
if public_api_host.nil? or public_api_host.empty?
  unless api[:nova][:ssl][:enabled]
    public_api_host = Chef::Recipe::Barclamp::Inventory.get_network_by_type(api, "public").address
  else
    public_api_host = 'public.'+api[:fqdn]
  end
end
api_protocol = api[:nova][:ssl][:enabled] ? 'https' : 'http'

keystone_register "nova api wakeup keystone" do
  protocol keystone_protocol
  host keystone_host
  port keystone_admin_port
  token keystone_token
  action :wakeup
end

keystone_register "register nova user" do
  protocol keystone_protocol
  host keystone_host
  port keystone_admin_port
  token keystone_token
  user_name keystone_service_user
  user_password keystone_service_password
  tenant_name keystone_service_tenant
  action :add_user
end

keystone_register "give nova user access" do
  protocol keystone_protocol
  host keystone_host
  port keystone_admin_port
  token keystone_token
  user_name keystone_service_user
  tenant_name keystone_service_tenant
  role_name "admin"
  action :add_access
end

keystone_register "register nova service" do
  protocol keystone_protocol
  host keystone_host
  port keystone_admin_port
  token keystone_token
  service_name "nova"
  service_type "compute"
  service_description "Openstack Nova Service"
  action :add_service
end

keystone_register "register ec2 service" do
  protocol keystone_protocol
  host keystone_host
  port keystone_admin_port
  token keystone_token
  service_name "ec2"
  service_type "ec2"
  service_description "EC2 Compatibility Layer"
  action :add_service
end

keystone_register "register nova endpoint" do
  protocol keystone_protocol
  host keystone_host
  port keystone_admin_port
  token keystone_token
  endpoint_service "nova"
  endpoint_region "RegionOne"
  endpoint_publicURL "#{api_protocol}://#{public_api_host}:8774/v2/$(tenant_id)s"
  endpoint_adminURL "#{api_protocol}://#{admin_api_host}:8774/v2/$(tenant_id)s"
  endpoint_internalURL "#{api_protocol}://#{admin_api_host}:8774/v2/$(tenant_id)s"
#  endpoint_global true
#  endpoint_enabled true
  action :add_endpoint_template
end

keystone_register "register nova ec2 endpoint" do
  protocol keystone_protocol
  host keystone_host
  port keystone_admin_port
  token keystone_token
  endpoint_service "ec2"
  endpoint_region "RegionOne"
  endpoint_publicURL "#{api_protocol}://#{public_api_host}:8773/services/Cloud"
  endpoint_adminURL "#{api_protocol}://#{admin_api_host}:8773/services/Admin"
  endpoint_internalURL "#{api_protocol}://#{admin_api_host}:8773/services/Cloud"
#  endpoint_global true
#  endpoint_enabled true
  action :add_endpoint_template
end

