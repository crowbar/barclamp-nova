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

if node.platform == "suse"
  case node[:nova][:libvirt_type]
    when "kvm"
      package "kvm"
      execute "loading kvm modules" do
        command "grep -q vmx /proc/cpuinfo && /sbin/modprobe kvm-intel; grep -q svm /proc/cpuinfo && /sbin/modprobe kvm-amd; /sbin/modprobe vhost-net"
      end
    when "qemu"
      package "qemu"
  end

  package "libvirt"

  service "libvirtd" do
    action [:enable, :restart]
  end
end

nova_package("compute")

#
# These two files are to handle: https://bugs.launchpad.net/ubuntu/+source/libvirt/+bug/996840
# This is a hack until that gets fixed.
# 
cookbook_file "/usr/lib/python2.7/dist-packages/nova/virt/libvirt/connection.py" do
  user "root"
  group "root"
  mode "0755"
  source "connection.py"
end

cookbook_file "/usr/lib/python2.7/dist-packages/nova/rootwrap/compute.py" do
  user "root"
  group "root"
  mode "0755"
  source "compute.py"
end


# ha_enabled activates Nova High Availability (HA) networking.
# The nova "network" and "api" recipes need to be included on the compute nodes and
# we must specify the --multi_host=T switch on "nova-manage network create".     

if node[:nova][:network][:ha_enabled]
  include_recipe "nova::api"
  include_recipe "nova::network"
end

if node.platform != "suse"
  template "/etc/nova/nova-compute.conf" do
    source "nova-compute.conf.erb"
    owner "root"
    group "root"
    mode 0644
    notifies :restart, "service[nova-compute]"
  end
end

# enable or disable the ksm setting (performance)
  
template "/etc/default/qemu-kvm" do
  source "qemu-kvm.erb" 
  variables({ 
    :kvm => node[:nova][:kvm] 
  })
  mode "0644"
end

execute "set ksm value" do
  command "echo #{node[:nova][:kvm][:ksm_enabled]} > /sys/kernel/mm/ksm/run"
end  
