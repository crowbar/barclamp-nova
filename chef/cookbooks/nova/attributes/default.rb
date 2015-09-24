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

default[:nova][:debug] = false
default[:nova][:max_header_line] = 16384

#
# Database Settings
#
default[:nova][:db][:password] = nil
default[:nova][:db][:user] = "nova"
default[:nova][:db][:database] = "nova"

# SQLAlchemy parameters
default[:nova][:db][:max_pool_size] = -1
default[:nova][:db][:max_overflow] = -1
default[:nova][:db][:pool_timeout] = -1
default[:nova][:db][:min_pool_size] = -1

# Feature settings
default[:nova][:use_migration] = false
default[:nova][:use_shared_instance_storage] = false

#
# Hypervisor Settings
#
default[:nova][:libvirt_type] = "kvm"
unless %w(suse).include?(node.platform)
  default[:nova][:libvirt_use_multipath] = false
else
  default[:nova][:libvirt_use_multipath] = true
end

#
# KVM Settings
#

default[:nova][:kvm][:ksm_enabled] = false

#
# VMware Settings
#

default[:nova][:vcenter][:host] = ""
default[:nova][:vcenter][:user] = ""
default[:nova][:vcenter][:password] = ""
default[:nova][:vcenter][:clusters] = []
default[:nova][:vcenter][:interface] = ""

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
default[:nova][:user] = "nova"
default[:nova][:group] = "nova"
default[:nova][:home_dir] = '/var/lib/nova'
default[:nova][:instances_path] = '/var/lib/nova/instances'
default[:nova][:vnc_keymap] = 'en-us'

default[:nova][:neutron_metadata_proxy_shared_secret] = ""
default[:nova][:neutron_url_timeout] = 30

default[:nova][:service_user] = "nova"
default[:nova][:service_password] = "nova"
default[:nova][:service_ssh_key] = ""

default[:nova][:rbd][:user] = ""
default[:nova][:rbd][:secret_uuid] = ""

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

default[:nova][:ports][:api_ec2] = 8773
default[:nova][:ports][:api] = 8774
default[:nova][:ports][:metadata] = 8775
default[:nova][:ports][:objectstore] = 3333
default[:nova][:ports][:novncproxy] = 6080
default[:nova][:ports][:xvpvncproxy] = 6081

default[:nova][:ha][:enabled] = false
default[:nova][:ha][:op][:monitor][:interval] = "10s"
# Ports to bind to when haproxy is used for the real ports
default[:nova][:ha][:ports][:api_ec2] = 5550
default[:nova][:ha][:ports][:api] = 5551
default[:nova][:ha][:ports][:metadata] = 5552
default[:nova][:ha][:ports][:objectstore] = 5553
default[:nova][:ha][:ports][:novncproxy] = 5554
default[:nova][:ha][:ports][:xvpvncproxy] = 5555

#
# Block device settings
#
default[:nova][:block_device][:allocate_retries] = 60
default[:nova][:block_device][:allocate_retries_interval] = 3
