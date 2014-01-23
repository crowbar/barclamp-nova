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

include_recipe "nova::database"
include_recipe "nova::config"

# Setup administrator credentials file
keystones = search_env_filtered(:node, "recipes:keystone\\:\\:server")
if keystones.length > 0
  keystone = keystones[0]
  keystone = node if keystone.name == node.name
else
  keystone = node
end

# For the public endpoint, we prefer the public name. If not set, then we
# use the IP address except for SSL, where we always prefer a hostname
# (for certificate validation).
keystone_protocol = keystone["keystone"]["api"]["protocol"]
public_keystone_host = keystone[:crowbar][:public_name]
if public_keystone_host.nil? or public_keystone_host.empty?
  unless keystone_protocol == "https"
    public_keystone_host = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "public").address
  else
    public_keystone_host = 'public.'+keystone[:fqdn]
  end
end
keystone_token = keystone["keystone"]["admin"]["token"] rescue nil
admin_username = keystone["keystone"]["admin"]["username"] rescue nil
admin_password = keystone["keystone"]["admin"]["password"] rescue nil
default_tenant = keystone["keystone"]["default"]["tenant"] rescue nil
keystone_service_port = keystone["keystone"]["api"]["service_port"] rescue nil
Chef::Log.info("Keystone server found at #{public_keystone_host}")

apis = search_env_filtered(:node, "recipes:nova\\:\\:api")
if apis.length > 0
  api = apis[0]
  api = node if api.name == node.name
else
  api = node
end
api_protocol = api[:nova][:ssl][:enabled] ? 'https' : 'http'
# For the public endpoint, we prefer the public name. If not set, then we
# use the IP address except for SSL, where we always prefer a hostname
# (for certificate validation).
public_api_host = api[:crowbar][:public_name]
if public_api_host.nil? or public_api_host.empty?
  unless api_protocol == 'https'
    public_api_host = Chef::Recipe::Barclamp::Inventory.get_network_by_type(api, "public").address
  else
    public_api_host = 'public.'+api[:fqdn]
  end
end
Chef::Log.info("API server found at #{public_api_host}")

if not node[:nova][:use_gitrepo]
  # install python-glanceclient on controller, to be able to upload images
  # from here
  glance_client = "python-glance"
  glance_client = "python-glanceclient" if %w(redhat centos suse).include?(node.platform)
  package glance_client do
    action :install
  end
end
template "/root/.openrc" do
  source "openrc.erb"
  owner "root"
  group "root"
  mode 0600
  variables(
    :keystone_protocol => keystone_protocol,
    :keystone_host => public_keystone_host,
    :keystone_service_port => keystone_service_port,
    :admin_username => admin_username,
    :admin_password => admin_password,
    :default_tenant => default_tenant,
    :nova_api_host => public_api_host,
    :nova_api_protocol => api_protocol
  )
end

