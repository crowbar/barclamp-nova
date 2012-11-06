#
# Cookbook Name:: nova
# Attributes:: default
#
# Copyright 2008-2011, Opscode, Inc.
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

::Chef::Node.send(:include, Opscode::OpenSSL::Password)


#
# Database Settings
#
default[:nova][:db][:password] = nil
default[:nova][:db][:user] = "nova"
default[:nova][:db][:database] = "nova"

#
# Hypervisor Settings
#
default[:nova][:libvirt_type] = "kvm"    

#
# KVM Settings                       
# 

default[:nova][:kvm][:ksm_enabled] = 0  # 0 = disable, 1 = enable


#
# Scheduler Settings
#
default[:nova][:scheduler][:ram_allocation_ratio] = "1.0"

#
# Shared Settings
#
default[:nova][:hostname] = "nova"
default[:nova][:my_ip] = ipaddress
default[:nova][:api] = ""
unless node[:platform] == 'suse'
    default[:nova][:user] = "nova"
else
    default[:nova][:user] = "openstack-nova"
end

#
# General network parameters
#

default[:nova][:networking_backend] = "quantum"
default[:nova][:network][:ha_enabled] = true
default[:nova][:network][:dhcp_enabled] = true
default[:nova][:network][:tenant_vlans] = true
default[:nova][:network][:allow_same_net_traffic] = true
default[:nova][:public_interface] = "eth0"
default[:nova][:routing_source_ip] = ipaddress
default[:nova][:fixed_range] = "10.0.0.0/8"
default[:nova][:floating_range] = "4.4.4.0/24"
default[:nova][:num_networks] = 1
default[:nova][:network_size] = 256
#
default[:nova][:network][:flat_network_bridge] = "br100"
default[:nova][:network][:flat_injected] = true
default[:nova][:network][:flat_dns] = "8.8.4.4"
default[:nova][:network][:flat_interface] = "eth0"
default[:nova][:network][:flat_network_dhcp_start] = "10.0.0.2"
default[:nova][:network][:vlan_interface] = "eth1"
default[:nova][:network][:vlan_start] = 100

default[:nova][:service_user] = "nova"
default[:nova][:service_password] = "nova"

#
# Transparent Hugepage Settings                       
# 
default[:nova][:hugepage][:tranparent_hugepage_enabled] = "always"
default[:nova][:hugepage][:tranparent_hugepage_defrag] = "always"
