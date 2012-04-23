#
# Cookbook Name:: nova
# Recipe:: vncproxy
#
# Copyright 2009, Example Com
# Copyright 2011, Dell Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "nova::config"

if node.platform == "suse"
    pkgs=%w[openstack-nova-vncproxy]
else
    pkgs=%w[python-numpy nova-vncproxy nova-console nova-consoleauth]
end

pkgs.each do |pkg|
  package pkg do
    action :upgrade
    options "--force-yes" if node.platform != "suse"
  end
end

if node.platform != "suse"
  execute "Fix permission Bug" do
    command "sed -i 's/nova$/root/g' /etc/init/nova-vncproxy.conf"
    action :run
  end
end

service "nova-vncproxy" do
  service_name "openstack-nova-vncproxy" if node.platform == "suse"
  supports :status => true, :restart => true
  action :enable
  subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
end

service "nova-consoleauth" do
  service_name "openstack-nova-consoleauth" if node.platform == "suse"
  supports :status => true, :restart => true
  action :enable
  subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
end
