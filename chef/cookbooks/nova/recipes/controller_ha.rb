# Copyright 2014 SUSE
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

unless node[:nova][:ha][:enabled]
  log "HA support for nova is disabled"
  return
end

log "HA support for nova is enabled"

cluster_vhostname = CrowbarPacemakerHelper.cluster_vhostname(node)

admin_net_db = Chef::DataBagItem.load('crowbar', 'admin_network').raw_data
cluster_admin_ip = admin_net_db["allocated_by_name"]["#{cluster_vhostname}.#{node[:domain]}"]["address"]

haproxy_loadbalancer "nova-api" do
  address "0.0.0.0"
  port node[:nova][:ports][:api]
  use_ssl node[:nova][:ssl][:enabled]
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "nova", "nova-multi-controller", "api")
  action :nothing
end.run_action(:create)

haproxy_loadbalancer "nova-api-ec2" do
  address "0.0.0.0"
  port node[:nova][:ports][:api_ec2]
  use_ssl node[:nova][:ssl][:enabled]
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "nova", "nova-multi-controller", "api_ec2")
  action :nothing
end.run_action(:create)

haproxy_loadbalancer "nova-metadata" do
  address cluster_admin_ip
  port node[:nova][:ports][:metadata]
  use_ssl false
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "nova", "nova-multi-controller", "metadata")
  action :nothing
end.run_action(:create)

haproxy_loadbalancer "nova-objectstore" do
  address "0.0.0.0"
  port node[:nova][:ports][:objectstore]
  use_ssl false
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "nova", "nova-multi-controller", "objectstore")
  action :nothing
end.run_action(:create)


if node[:nova][:use_novnc]
  haproxy_loadbalancer "nova-novncproxy" do
    address "0.0.0.0"
    port node[:nova][:ports][:novncproxy]
    use_ssl node[:nova][:novnc][:ssl][:enabled]
    servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "nova", "nova-multi-controller", "novncproxy")
    action :nothing
  end.run_action(:create)
else
  haproxy_loadbalancer "nova-xvpvncproxy" do
    address "0.0.0.0"
    port node[:nova][:ports][:xvpvncproxy]
    use_ssl false
    servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "nova", "nova-multi-controller", "xvpvncproxy")
    action :nothing
  end.run_action(:create)
end
