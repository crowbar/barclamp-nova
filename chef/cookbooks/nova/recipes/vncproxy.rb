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

unless %w(redhat centos suse).include?(node.platform)
  pkgs=%w[python-numpy nova-console nova-consoleauth]
  pkgs.each do |pkg|
    package pkg do
      action :install
      options "--force-yes"
    end
  end
end

# forcing novnc is deliberate on suse
if node[:nova][:use_novnc]
  if %w(redhat centos suse).include?(node.platform)
    package "openstack-nova-novncproxy" do
      action :install
    end
    unless %w(redhat centos).include?(node.platform)
      package "openstack-nova-consoleauth" do
        action :install
      end
    end
  else
    package "nova-novncproxy" do
      action :install
      options "--force-yes"
    end
    execute "Fix permission Bug" do
      command "sed -i 's/nova$/root/g' /etc/init/nova-novncproxy.conf"
      action :run
    end
  end
  service "nova-novncproxy" do
    service_name "openstack-nova-novncproxy" if %w(redhat centos suse).include?(node.platform)
    supports :status => true, :restart => true
    action [:enable, :start]
    subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
    provider Chef::Provider::CrowbarPacemakerService if node[:nova][:ha][:enabled]
  end
end
service "nova-consoleauth" do
  service_name "openstack-nova-consoleauth" if %w(redhat centos suse).include?(node.platform)
  supports :status => true, :restart => true
  action [:enable, :start]
  subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
  provider Chef::Provider::CrowbarPacemakerService if node[:nova][:ha][:enabled]
end
