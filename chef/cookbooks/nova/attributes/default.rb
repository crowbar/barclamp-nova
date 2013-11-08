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

default[:nova][:use_migration] = false
default[:nova][:use_shared_instance_storage] = false

#
# Hypervisor Settings
#
default[:nova][:libvirt_type] = "kvm"

#
# KVM Settings
#

default[:nova][:kvm][:ksm_enabled] = false


#
# Scheduler Settings
#
default[:nova][:scheduler][:ram_allocation_ratio] = 1.0
default[:nova][:scheduler][:cpu_allocation_ratio] = 16.0

#
# Shared Settings
#
default[:nova][:hostname] = "nova"
default[:nova][:my_ip] = ipaddress
unless %w(suse).include?(node.platform)
    default[:nova][:user] = "nova"
    default[:nova][:group] = "nova"
else
    default[:nova][:user] = "openstack-nova"
    default[:nova][:group] = "openstack-nova"
end
default[:nova][:instances_path] = '/var/lib/nova/instances'

#
# General network parameters
#

default[:nova][:networking_backend] = "neutron"
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
default[:nova][:neutron_metadata_proxy_shared_secret] = ""
#
default[:nova][:network][:flat_network_bridge] = "br100"
default[:nova][:network][:flat_injected] = true
default[:nova][:network][:flat_dns] = "8.8.4.4"
default[:nova][:network][:flat_interface] = "eth0"
default[:nova][:network][:vlan_interface] = "eth1"
default[:nova][:network][:vlan_start] = 100

default[:nova][:service_user] = "nova"
default[:nova][:service_password] = "nova"
default[:nova][:service_ssh_key] = ""

default[:nova][:ssl][:enabled] = false
default[:nova][:ssl][:certfile] = "/etc/nova/ssl/certs/signing_cert.pem"
default[:nova][:ssl][:keyfile] = "/etc/nova/ssl/private/signing_key.pem"
default[:nova][:ssl][:generate_certs] = false
default[:nova][:ssl][:insecure] = false
default[:nova][:ssl][:cert_required] = false
default[:nova][:ssl][:ca_certs] = "/etc/nova/ssl/certs/ca.pem"

default[:nova][:novnc][:ssl][:enabled] = false
default[:nova][:novnc][:ssl][:certfile] = ""
default[:nova][:novnc][:ssl][:keyfile] = ""

#
# Transparent Hugepage Settings
#
default[:nova][:hugepage][:tranparent_hugepage_enabled] = "always"
default[:nova][:hugepage][:tranparent_hugepage_defrag] = "always"
