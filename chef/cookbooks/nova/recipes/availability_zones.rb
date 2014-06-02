#
# Cookbook Name:: nova
# Recipe:: availability_zones
#
# Copyright 2014, SUSE
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

cookbook_file "crowbar-nova-set-availability-zone" do
  source "crowbar-nova-set-availability-zone"
  path "/usr/bin/crowbar-nova-set-availability-zone"
  mode "0755"
end

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

nova_insecure = node[:nova][:ssl][:enabled] && node[:nova][:ssl][:insecure]

command = [ "/usr/bin/crowbar-nova-set-availability-zone" ]
command << "--os-username"
command << keystone_settings['admin_user']
command << "--os-password"
command << keystone_settings['admin_password']
command << "--os-tenant-name"
command << keystone_settings['default_tenant']
command << "--os-auth-url"
command << keystone_settings['internal_auth_url']
if keystone_settings['insecure'] || nova_insecure
  command << "--insecure"
end

search_env_filtered(:node, "roles:nova-multi-compute-*") do |n|
  availability_zone = ""
  unless n[:crowbar_wall].nil? or n[:crowbar_wall][:openstack].nil?
    availability_zone = n[:crowbar_wall][:openstack][:availability_zone]
  end

  node_command = command.clone
  node_command << n.hostname
  # we need an array for the command to avoid command injection with this part
  node_command << availability_zone

  # Note: if availability_zone is "", then the command will move the host to
  # the default availability zone, which is what we want
  execute "Set availability zone for #{n.hostname}" do
    command node_command
    timeout 15
    returns [0, 68]
    action :nothing
    subscribes :run, "execute[trigger-nova-az-config]", :delayed
  end
end

# This is to trigger all the above "execute" resources to run :delayed, so that
# they run at the end of the chef-client run, after the nova service have been
# restarted (in case of a config change)
execute "trigger-nova-az-config" do
  command "true"
end
