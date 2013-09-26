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

if %w(redhat centos suse).include?(node.platform)
  package "libvirt"

  template "/etc/libvirt/libvirtd.conf" do
    source "libvirtd.conf.erb"
    group "root"
    owner "root"
    mode 0644
    variables(
      :libvirtd_listen_tcp => node[:nova]["use_migration"] ? 1 : 0,
      :libvirtd_listen_addr => Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address,
      :libvirtd_auth_tcp => node[:nova]["use_migration"] ? "none" : "sasl"
    )
    notifies :restart, "service[libvirtd]", :delayed
  end

  case node[:nova][:libvirt_type]
    when "kvm"
      package "kvm"
      execute "loading kvm modules" do
        command "grep -q vmx /proc/cpuinfo && /sbin/modprobe kvm-intel; grep -q svm /proc/cpuinfo && /sbin/modprobe kvm-amd; /sbin/modprobe vhost-net"
      end

      set_boot_kernel_and_trigger_reboot
    when "xen"
      %w{kernel-xen xen xen-tools openvswitch-kmp-xen}.each do |pkg|
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

  libvirt_restart_needed = false

  # change libvirt to run qemu as user qemu
  if %w(suse).include?(node.platform)
    ruby_block "edit qemu config" do
      block do
        rc = Chef::Util::FileEdit.new("/etc/libvirt/qemu.conf")

        # make sure to only set qemu:kvm for kvm and qemu deployments, use
        # system defaults for xen
        if ['kvm','qemu'].include?(node[:nova][:libvirt_type])
          rc.search_file_replace_line(/^[ #]*user *=/, 'user = "qemu"')
          rc.search_file_replace_line(/^[ #]*group *=/, 'group = "kvm"')
        else
          rc.search_file_replace_line(/^ *user *=/, '#user = "root"')
          rc.search_file_replace_line(/^ *group *=/, '#group = "root"')
        end

        if rc.file_edited?
          rc.write_file
          libvirt_restart_needed = true
        end
      end
    end
  else
    if ['kvm','qemu'].include?(node[:nova][:libvirt_type])
      libvirt_user = "qemu"
      libvirt_group = "kvm"
    else
      libvirt_user = "root"
      libvirt_group = "root"
    end

    service "libvirtd" do
      action [:enable, :start]
    end

    bash "edit qemu config" do
      only_if "cat /etc/libvirt/qemu.conf | grep 'user =' | grep -q -v '#{libvirt_user}' || cat /etc/libvirt/qemu.conf | grep 'group =' | grep -q -v '#{libvirt_group}'"
      code <<-EOH
       sed -i 's|user *=.*|user = "#{libvirt_user}"|g' /etc/libvirt/qemu.conf
       sed -i 's|group *=.*|group = "#{libvirt_group}"|g' /etc/libvirt/qemu.conf
      EOH
      notifies :restart, "service[libvirtd]"
    end
  end

  service "libvirtd" do
    action [:enable, :start]
  end

  if libvirt_restart_needed
    service "libvirtd" do
      action [:restart], :delayed
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

cookbook_file "/etc/nova/nova-compute.conf" do
  source "nova-compute.conf"
  owner "root"
  group "root"
  mode 0644
  notifies :restart, "service[nova-compute]"
end unless node.platform == "suse"

# kill all the libvirt default networks.
execute "Destroy the libvirt default network" do
  command "virsh net-destroy default"
  only_if "virsh net-list |grep -q default"
end


env_filter = " AND nova_config_environment:#{node[:nova][:config][:environment]}"
nova_controller = search(:node, "roles:nova-multi-controller#{env_filter}")

if !nova_controller.nil? and nova_controller.length > 0 and nova_controller[0].name != node.name

  nova_controller_ip =  Chef::Recipe::Barclamp::Inventory.get_network_by_type(nova_controller[0], "admin").address
  mount node[:nova][:instances_path] do
    action node[:nova]["use_shared_instance_storage"] ? [:mount, :enable] : [:umount, :disable]
    fstype "nfs"
    options "rw,auto"
    device nova_controller_ip + ":" +  node[:nova][:instances_path]
  end

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
end if node.platform == "ubuntu"

template "/usr/sbin/crowbar-compute-set-sys-options" do
  source "crowbar-compute-set-sys-options.erb"
  variables({
    :ksm_enabled => node[:nova][:kvm][:ksm_enabled] ? 1 : 0,
    :tranparent_hugepage_enabled => node[:nova][:hugepage][:tranparent_hugepage_enabled],
    :tranparent_hugepage_defrag => node[:nova][:hugepage][:tranparent_hugepage_defrag]
  })
  mode "0755"
end

cookbook_file "/etc/cron.d/crowbar-compute-set-sys-options-at-boot" do
  source "crowbar-compute-set-sys-options-at-boot"
end

execute "run crowbar-compute-set-sys-options" do
  command "/usr/sbin/crowbar-compute-set-sys-options"
end

execute "set vhost_net module" do
  command "grep -q 'vhost_net' /etc/modules || echo 'vhost_net' >> /etc/modules"
end

if node[:nova][:networking_backend]=="quantum" and not %w(redhat centos suse).include?(node.platform)
  #since using native ovs we have to gain acess to lower networking functions
  service "libvirt-bin" do
    action :nothing
    supports :status => true, :start => true, :stop => true, :restart => true
  end
  cookbook_file "/etc/libvirt/qemu.conf" do
    owner "root"
    group "root"
    mode "0644"
    source "qemu.conf"
    notifies :restart, "service[libvirt-bin]"
  end
end
