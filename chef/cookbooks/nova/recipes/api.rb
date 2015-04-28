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

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

# XXX this is no different from the file provided in the package, but
# since we used to have a configured template here, we need to make sure
# that it gets overwritten specifically since it used to contain
# auth_token configuration options which conflict with the ones in
# nova.conf and the packages won't overwrite a modified file.
# This block can be removed when either nova does not read auth_token
# configuration from api-paste.ini or we are sure that the target
# machine no longer has an api-paste.ini file with the auth_token settings
cookbook_file "api-paste.ini" do
  path "/etc/nova/api-paste.ini"
  owner "root"
  group node[:nova][:group]
  mode "0640"
  action :create
end

nova_package "api" do
  use_pacemaker_provider node[:nova][:ha][:enabled]
end
nova_package "objectstore" do
  use_pacemaker_provider node[:nova][:ha][:enabled]
end

apis = search_env_filtered(:node, "recipes:nova\\:\\:api")
if apis.length > 0
  api = apis[0]
  api = node if api.name == node.name
else
  api = node
end

api_ha_enabled = api[:nova][:ha][:enabled]
admin_api_host = CrowbarHelper.get_host_for_admin_url(api, api_ha_enabled)
public_api_host = CrowbarHelper.get_host_for_public_url(api, api[:nova][:ssl][:enabled], api_ha_enabled)
api_port = api[:nova][:ports][:api]
api_ec2_port = api[:nova][:ports][:api_ec2]

api_protocol = api[:nova][:ssl][:enabled] ? 'https' : 'http'

crowbar_pacemaker_sync_mark "wait-nova_register"

keystone_register "nova api wakeup keystone" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  action :wakeup
end

keystone_register "register nova user" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  user_name keystone_settings['service_user']
  user_password keystone_settings['service_password']
  tenant_name keystone_settings['service_tenant']
  action :add_user
end

keystone_register "give nova user access" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  user_name keystone_settings['service_user']
  tenant_name keystone_settings['service_tenant']
  role_name "admin"
  action :add_access
end

keystone_register "register nova service" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  service_name "nova"
  service_type "compute"
  service_description "Openstack Nova Service"
  action :add_service
end

keystone_register "register ec2 service" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  service_name "ec2"
  service_type "ec2"
  service_description "EC2 Compatibility Layer"
  action :add_service
end

keystone_register "register computev21 service" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  service_name "novav21"
  service_type "computev21"
  service_description "Openstack Nova Compute Service V2.1"
  action :add_service
end

keystone_register "register nova endpoint" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  endpoint_service "nova"
  endpoint_region keystone_settings['endpoint_region']
  endpoint_publicURL "#{api_protocol}://#{public_api_host}:#{api_port}/v2/$(tenant_id)s"
  endpoint_adminURL "#{api_protocol}://#{admin_api_host}:#{api_port}/v2/$(tenant_id)s"
  endpoint_internalURL "#{api_protocol}://#{admin_api_host}:#{api_port}/v2/$(tenant_id)s"
#  endpoint_global true
#  endpoint_enabled true
  action :add_endpoint_template
end

keystone_register "register nova ec2 endpoint" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  endpoint_service "ec2"
  endpoint_region keystone_settings['endpoint_region']
  endpoint_publicURL "#{api_protocol}://#{public_api_host}:#{api_ec2_port}/services/Cloud"
  endpoint_adminURL "#{api_protocol}://#{admin_api_host}:#{api_ec2_port}/services/Admin"
  endpoint_internalURL "#{api_protocol}://#{admin_api_host}:#{api_ec2_port}/services/Cloud"
#  endpoint_global true
#  endpoint_enabled true
  action :add_endpoint_template
end

keystone_register "register computev21 endpoint" do
  protocol keystone_settings['protocol']
  insecure keystone_settings['insecure']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  endpoint_service "novav21"
  endpoint_region keystone_settings['endpoint_region']
  endpoint_publicURL "#{api_protocol}://#{public_api_host}:#{api_port}/v2.1/$(tenant_id)s"
  endpoint_adminURL "#{api_protocol}://#{admin_api_host}:#{api_port}/v2.1/$(tenant_id)s"
  endpoint_internalURL "#{api_protocol}://#{admin_api_host}:#{api_port}/v2.1/$(tenant_id)s"
  action :add_endpoint_template
end

crowbar_pacemaker_sync_mark "create-nova_register"
