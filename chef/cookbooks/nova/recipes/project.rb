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
keystone_settings = NovaHelper.keystone_settings(node)

apis = search_env_filtered(:node, "recipes:nova\\:\\:api")
if apis.length > 0
  api = apis[0]
  api = node if api.name == node.name
else
  api = node
end
api_protocol = api[:nova][:ssl][:enabled] ? 'https' : 'http'

ha_enabled = false
public_api_host = CrowbarHelper.get_host_for_public_url(api, api[:nova][:ssl][:enabled], ha_enabled)
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
    :keystone_settings => keystone_settings,
    :nova_api_host => public_api_host,
    :nova_api_protocol => api_protocol
  )
end

