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
include_recipe "nova::database"

def set_boot_kernel_and_trigger_reboot(flavor='default')
  # only default and xen flavor is supported by this helper right now
  default_boot = 0
  current_default = nil

  # parse menu.lst, to find boot index for selected flavor
  File.open('/boot/grub/menu.lst') do |f|
    f.lines.each do |line|
      current_default = line.scan(/\d/).first.to_i if line.start_with?('default')

      if line.start_with?('title')
        if flavor.eql?('xen')
          # found boot index
          break if line.include?('Xen')
        else
          # take first kernel as default, unless we are searching for xen
          # kernel
          break
        end

        default_boot += 1
      end
      
    end
  end

  # change default option for /boot/grub/menu.lst
  unless current_default.eql?(default_boot)
    puts "changed grub default to #{default_boot}"
    %x[sed -i -e "s;^default.*;default #{default_boot};" /boot/grub/menu.lst]
  end

  # trigger reboot through reboot_handler, if kernel-$flavor is not yet
  # running
  unless %x[uname -r].include?(flavor)
    node.run_state[:reboot] = true
  end
end


if node.platform == "suse"
  case node[:nova][:libvirt_type]
    when "kvm"
      package "kvm"
      execute "loading kvm modules" do
        command "grep -q vmx /proc/cpuinfo && /sbin/modprobe kvm-intel; grep -q svm /proc/cpuinfo && /sbin/modprobe kvm-amd; /sbin/modprobe vhost-net"
      end

      set_boot_kernel_and_trigger_reboot
    when "xen"
      %w{kernel-xen xen xen-tools}.each do |pkg|
        package pkg do
          action :install
        end
      end

      set_boot_kernel_and_trigger_reboot('xen')
    when "qemu"
      package "kvm"
    when "lxc"
      package "lxc"

      service "boot.cgroup" do
        action [:enable, :start]
      end
  end

  package "libvirt"

  # change libvirt to run qemu as user qemu
  ruby_block "edit qemu config" do
    block do
      rc = Chef::Util::FileEdit.new("/etc/libvirt/qemu.conf")

      # make sure to only set qemu:kvm for kvm and qemu deployments, use
      # system defaults for xen
      if ['kvm','qemu'].include?(node[:nova][:libvirt_type])
        rc.search_file_replace_line(/user.*=/, 'user = "qemu"')
        rc.search_file_replace_line(/group.*=/, 'group = "kvm"')
      else
        rc.search_file_replace_line(/user.*=/, '#user = "root"')
        rc.search_file_replace_line(/group.*=/, '#group = "root"')
      end
      rc.write_file
    end
  end

  service "libvirtd" do
    action [:enable, :restart]
  end
end

nova_package("compute")

# ha_enabled activates Nova High Availability (HA) networking.
# The nova "network" and "api" recipes need to be included on the compute nodes and
# we must specify the --multi_host=T switch on "nova-manage network create". 
if node[:nova][:network][:ha_enabled]
  include_recipe "nova::api"
  include_recipe "nova::network"
end

if node[:nova][:volume][:type] == "rados"

  ceph_kmps = ["ceph-kmp-default"]
  ceph_kmps << "ceph-kmp-xen" if node[:nova][:libvirt_type].eql?('xen')

  ceph_kmps.each do |pkg|
    package pkg do
      action :upgrade
    end
  end

  execute "loading rbd kernel module" do
    command "/sbin/modprobe rbd"
  end

  # make sure to load rbd via MODULES_LOADED_ON_BOOT in /etc/sysconfig/kernel
  # (default install has MODULES_LOADED_ON_BOOT="")
  ruby_block "edit sysconfig kernel" do
    block do
      rc = Chef::Util::FileEdit.new("/etc/sysconfig/kernel")
      rc.search_file_replace_line(/^MODULES_LOADED_ON_BOOT=/, 'MODULES_LOADED_ON_BOOT="rbd"')
      rc.write_file
    end
  end
                              
  file node[:nova][:volume][:ceph_secret_file] do
    owner "openstack-nova"
    group "root"
    mode 0640
    content node[:nova][:volume][:ceph_secret]
    action :create
  end

else
  # enable and start open-iscsi, as this is needed for nova-volume to work
  # properly
  service "open-iscsi" do
    supports :status => true, :restart => true
    action [ :enable, :start ]
  end
end
