#
# Cookbook Name:: nova
# Recipe:: compute
#
# Copyright 2010, Opscode, Inc.
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

include_recipe "nova::config"

package "mysql-client"

nova_package("compute")

# ha_enabled activates Nova High Availability (HA) networking.
# The nova "network" and "api" recipes need to be included on the compute nodes and
# we must specify the --multi_host=T switch on "nova-manage network create". 
if node[:nova][:network][:ha_enabled]
  include_recipe "nova::api"
  include_recipe "nova::network"
end

template "/etc/nova/nova-compute.conf" do
  source "nova-compute.conf.erb"
  owner "root"
  group "root"
  mode 0644
  notifies :restart, "service[nova-compute]"
end

