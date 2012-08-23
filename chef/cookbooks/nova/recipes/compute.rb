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

if node[:nova][:networking_backend]=="quantum"
#unless node[:nova][:use_gitrepo]
#  package "quantum" do
#    action :install
#  end
#else
  include_recipe "nova::quantum"
#  pfs_and_install_deps "quantum" do
#    cookbook "quantum"
#    cnode quantum
#  end
#end
end

include_recipe "nova::config"
include_recipe "database::client"

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

  libvirt_restart_needed = false

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

      libvirt_restart_needed = true if rc.file_edited
      rc.write_file
    end
  end

  service "libvirtd" do
    action [:enable, :start]
  end

  if libvirt_restart_needed
    service "libvirtd" do
      action [:restart]
    end
  end
end

nova_package("compute")

# ha_enabled activates Nova High Availability (HA) networking.
# The nova "network" and "api" recipes need to be included on the compute nodes and
# we must specify the --multi_host=T switch on "nova-manage network create".     

if node[:nova][:network][:ha_enabled] and node[:nova][:networking_backend]=='nova-network'
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

# kill all the libvirt default networks.
execute "Destroy the libvirt default network" do
  command "virsh net-destroy default"
  only_if "virsh net-list |grep -q default"
end

link "/etc/libvirt/qemu/networks/autostart/default.xml" do
  action :delete
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

execute "set tranparent huge page enabled support" do
  # note path to setting is OS dependent
  # redhat /sys/kernel/mm/redhat_transparent_hugepage/enabled
  # Below will work on both Ubuntu and SLES
  command "echo #{node[:nova][:hugepage][:tranparent_hugepage_enabled]} > /sys/kernel/mm/transparent_hugepage/enabled"
  # not_if 'grep -q \\[always\\] /sys/kernel/mm/transparent_hugepage/enabled'
end

execute "set tranparent huge page defrag support" do
  command "echo #{node[:nova][:hugepage][:tranparent_hugepage_defrag]} > /sys/kernel/mm/transparent_hugepage/defrag"
end

execute "set vhost_net module" do
  command "grep -q 'vhost_net' /etc/modules || echo 'vhost_net' >> /etc/modules"
end

execute "IO scheduler" do
  command "find /sys/block -type l -name 'sd*' -exec sh -c 'echo deadline > {}/queue/scheduler' \\;"
end  

if node[:nova][:networking_backend]=="quantum" and node.platform != "suse"
  #since using native ovs we have to gain acess to lower networking functions
  service "libvirt-bin" do
    action :nothing
    supports :status => true, :start => true, :stop => true, :restart => true
  end
  cookbook_file "/etc/libvirt/qemu.conf" do
    user "root"
    group "root"
    mode "0644"
    source "qemu.conf"
    notifies :restart, "service[libvirt-bin]"
  end
end
