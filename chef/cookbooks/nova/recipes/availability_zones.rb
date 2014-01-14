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

keystones = search_env_filtered(:node, "recipes:keystone\\:\\:server")
if keystones.length > 0
  keystone = keystones[0]
  keystone = node if keystone.name == node.name
else
  keystone = node
end

keystone_protocol = keystone["keystone"]["api"]["protocol"]
keystone_host = keystone[:fqdn]
keystone_service_port = keystone["keystone"]["api"]["service_port"]
keystone_insecure = keystone_protocol == 'https' && keystone[:keystone][:ssl][:insecure]

nova_insecure = node[:nova][:ssl][:enabled] && node[:nova][:ssl][:insecure]

admin_username = keystone["keystone"]["admin"]["username"]
admin_password = keystone["keystone"]["admin"]["password"]
default_tenant = keystone["keystone"]["default"]["tenant"]

command = [ "/usr/bin/crowbar-nova-set-availability-zone" ]
command << "--os-username"
command << admin_username
command << "--os-password"
command << admin_password
command << "--os-tenant-name"
command << default_tenant
command << "--os-auth-url"
command << "#{keystone_protocol}://#{keystone_host}:#{keystone_service_port}/v2.0/"
if keystone_insecure || nova_insecure
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
  end
end
