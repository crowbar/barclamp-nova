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

include_recipe "nova::neutron"
include_recipe "nova::config"

def set_boot_kernel_and_trigger_reboot(flavor='default')
  # only default and xen flavor is supported by this helper right now
  if node.platform == "suse" && node.platform_version.to_f >= 12.0
    default_boot = 'SLES12'
    grub_env = %x[grub2-editenv list]
    if grub_env.include?("saved_entry")
      current_default = grub_env.strip.split("=")[1]
    else
      current_default = nil
    end

    # parse grub config, to find boot index for selected flavor
    File.open('/boot/grub2/grub.cfg') do |f|
      f.each_line do |line|
        if line.start_with?('menuentry')
          default_boot = line.sub(/^menuentry '([^']*)'.*$/,'\1').strip
          if flavor.eql?('xen')
            # found boot index
            break if line.include?('Xen')
          else
            # take first non-xen kernel as default
            break unless line.include?('Xen')
          end
        end
      end
    end
    # change default option for grub config
    unless current_default.eql?(default_boot)
      Chef::Log.info("changed grub default to #{default_boot}")
      %x[grub2-set-default '#{default_boot}']
    end
  else
    default_boot = 0
    current_default = nil

    # parse grub config, to find boot index for selected flavor
    File.open('/boot/grub/menu.lst') do |f|
      f.each_line do |line|
        current_default = line.scan(/\d/).first.to_i if line.start_with?('default')
        if line.start_with?('title')
          if flavor.eql?('xen')
            # found boot index
            break if line.include?('Xen')
          else
            # take first non-xen kernel as default
            break unless line.include?('Xen')
          end
          default_boot += 1
        end
      end
    end
    # change default option for grub config
    unless current_default.eql?(default_boot)
      Chef::Log.info("changed grub default to #{default_boot}")
      %x[sed -i -e "s;^default.*;default #{default_boot};" /boot/grub/menu.lst]
    end
  end

  # trigger reboot through reboot_handler, if kernel-$flavor is not yet
  # running
  unless %x[uname -r].include?(flavor)
    node.run_state[:reboot] = true
  end
end

if %w(redhat centos suse).include?(node.platform)
  # make sure that the libvirt package is present before other actions try to access /etc/qemu.conf
  package "libvirt" do
    action :nothing
  end.run_action(:install)

  # Generate a UUID, as DMI's system uuid is unreliable
  if node[:nova][:host_uuid].nil?
    node.normal[:nova][:host_uuid] = `uuidgen`.strip
    node.save
  end

  template "/etc/libvirt/libvirtd.conf" do
    source "libvirtd.conf.erb"
    group "root"
    owner "root"
    mode 0644
    variables(
      :libvirtd_host_uuid => node[:nova][:host_uuid],
      :libvirtd_listen_tcp => node[:nova]["use_migration"] ? 1 : 0,
      :libvirtd_listen_addr => Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address,
      :libvirtd_auth_tcp => node[:nova]["use_migration"] ? "none" : "sasl"
    )
    notifies :restart, "service[libvirtd]", :delayed
  end

  # Start open-iscsi daemon, since nova-compute is going to use it and stumble over the
  # "starting daemon" messages otherwise
  service "open-iscsi" do
    supports :status => true, :start => true, :stop => true, :restart => true
    action [:enable, :start]
    if node.platform == "suse"
      if node.platform_version.to_f < 12
        # Workaround broken open-iscsi init scripts that return a failed code
        # but start the service anyway. run a status command afterwards to
        # see what the real status is (bnc#885834)
        start_command "/etc/init.d/open-iscsi start; /etc/init.d/open-iscsi status"
      else
        service_name "iscsid"
      end
    end
  end

  case node[:nova][:libvirt_type]
    when "kvm", "qemu"
      if node.platform_version.to_f >= 12.0
        package "qemu"
      else
        package "kvm"
      end

      # Install Ceph integration if needed
      cinder_servers = search_env_filtered(:node, "roles:cinder-controller") || []
      if cinder_servers.length > 0
        cinder_servers[0][:cinder][:volumes].each do |volume|
          next if volume['backend_driver'] != "rbd"

          package "python-ceph"
          package "ceph-common"

          break
        end
      end

      set_boot_kernel_and_trigger_reboot

      if node[:nova][:libvirt_type] == "kvm"
        if node.platform_version.to_f >= 12.0
          package "qemu-kvm"
          package "qemu-block-rbd"
        end

        # load modules only when appropriate kernel is present
        execute "loading kvm modules" do
          command <<-EOF
              grep -qw vmx /proc/cpuinfo && /sbin/modprobe kvm-intel
              grep -qw svm /proc/cpuinfo && /sbin/modprobe kvm-amd
              /sbin/modprobe vhost-net
              /sbin/modprobe nbd
            EOF
          only_if { %x[uname -r].include?('default') }
        end
      end

    when "xen"
      %w{kernel-xen xen xen-tools openvswitch-kmp-xen}.each do |pkg|
        package pkg do
          action :install
        end
      end

      service "xend" do
        action :nothing
        supports :status => true, :start => true, :stop => true, :restart => true
        # restart xend only when xen kernel is already present
        only_if { %x[uname -r].include?('xen') }
      end

      template "/etc/xen/xend-config.sxp" do
        source "xend-config.sxp.erb"
        group "root"
        owner "root"
        mode 0644
        variables(
          :node_platform => node[:platform],
          :libvirt_migration => node[:nova]["use_migration"],
          :shared_instances => node[:nova]["use_shared_instance_storage"],
          :libvirtd_listen_tcp => node[:nova]["use_migration"] ? 1 : 0,
          :libvirtd_listen_addr => Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
        )
        notifies :restart, "service[xend]", :delayed
      end

      set_boot_kernel_and_trigger_reboot('xen')
    when "vmware"
      package "python-suds"
    when "lxc"
      package "lxc"

      service "boot.cgroup" do
        action [:enable, :start]
      end
  end

  # change libvirt to run qemu as user qemu
  # make sure to only set qemu:kvm for kvm and qemu deployments, use
  # system defaults for xen
  if ['kvm','qemu'].include?(node[:nova][:libvirt_type])
    libvirt_user = "qemu"
    libvirt_group = "kvm"
  else
    libvirt_user = "root"
    libvirt_group = "root"
  end

  template "/etc/libvirt/qemu.conf" do
    source "qemu.conf.sle12.erb" if node.platform == "suse" && node.platform_version.to_f >= 12.0
    group "root"
    owner "root"
    mode 0644
    variables(
        :user => libvirt_user,
        :group => libvirt_group
    )
    notifies :restart, "service[libvirtd]"
  end

  service "libvirtd" do
    action [:enable, :start]
  end
end

nova_package("compute")

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

# Note: since we do not allow shared storage with a cluster, we know that the
# first controller is the right one to use (ie, the only one)
if !nova_controller.nil? and nova_controller.length > 0 and nova_controller[0].name != node.name
  nova_controller_ip =  Chef::Recipe::Barclamp::Inventory.get_network_by_type(nova_controller[0], "admin").address
  mount node[:nova][:instances_path] do
    action node[:nova]["use_shared_instance_storage"] ? [:mount, :enable] : [:umount, :disable]
    fstype "nfs"
    options "rw,auto"
    device nova_controller_ip + ":" +  node[:nova][:instances_path]
  end

end

unless node[:nova][:user].empty? or node["etc"]["passwd"][node[:nova][:user]].nil?
  nova_home_dir = node["etc"]["passwd"][node[:nova][:user]]["dir"]
end


if node[:nova][:use_gitrepo]
  # This account needs to be ssh'able, so must have a login shell
  user node[:nova][:user] do
    shell "/bin/bash"
    supports :manage_home => true
    home node[:nova][:home_dir]
    gid "libvirtd"
  end
end

# Create and distribute ssh keys for nova user on all compute nodes

# if for some reason, we only have one of the two keys, we recreate the keys
# (no need to check the case where public key doesn't exist, as the execute
# resource deals with that)
if ::File.exist?("#{node[:nova][:home_dir]}/.ssh/id_rsa.pub") and !::File.exist?("#{node[:nova][:home_dir]}/.ssh/id_rsa")
  file "#{node[:nova][:home_dir]}/.ssh/id_rsa.pub" do
    action :delete
  end
end

execute "Create Nova SSH key" do
  command "su #{node[:nova][:user]} -c \"ssh-keygen -q -t rsa  -P '' -f '#{node[:nova][:home_dir]}/.ssh/id_rsa'\""
  creates "#{node[:nova][:home_dir]}/.ssh/id_rsa.pub"
  only_if { ::File.exist?(node[:nova][:home_dir]) }
end

ruby_block "nova_read_ssh_public_key" do
  block do
    service_ssh_key = File.read("#{node[:nova][:home_dir]}/.ssh/id_rsa.pub")
    if node[:nova][:service_ssh_key] != service_ssh_key
      node.set[:nova][:service_ssh_key] = service_ssh_key
      node.save
    end
  end
  only_if { ::File.exist?("#{node[:nova][:home_dir]}/.ssh/id_rsa.pub") }
end

ssh_auth_keys = ""
search_env_filtered(:node, "roles:nova-multi-compute-kvm") do |n|
    ssh_auth_keys += n[:nova][:service_ssh_key]
end
search_env_filtered(:node, "roles:nova-multi-compute-xen") do |n|
    ssh_auth_keys += n[:nova][:service_ssh_key]
end
search_env_filtered(:node, "roles:nova-multi-compute-qemu") do |n|
    ssh_auth_keys += n[:nova][:service_ssh_key]
end

file "#{node[:nova][:home_dir]}/.ssh/authorized_keys" do
  content ssh_auth_keys
  owner node[:nova][:user]
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

if node[:nova][:libvirt_use_multipath]
  package "multipath-tools"

  service "multipathd" do
    action [:enable, :start]
  end

  service "boot.multipath" do
    action [:enable]
    # on SLES12 there is no boot.multipath service, because of systemd
    not_if { node.platform == "suse" && node.platform_version.to_f >= 12.0 }
  end
end

unless %w(redhat centos suse).include?(node.platform)
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

# Set our availability zone
command_no_arg = NovaAvailabilityZone.fetch_set_az_command_no_arg(node, @cookbook_name)
command = NovaAvailabilityZone.add_arg_to_set_az_command(command_no_arg, node)

execute "Set availability zone for #{node.hostname}" do
  command command
  timeout 15
  # Any exit code in the range 60-69 is a tempfail
  returns [0] + (60..69).to_a
  action :nothing
  subscribes :run, "execute[trigger-nova-own-az-config]", :delayed
end

# This is to trigger all the above "execute" resources to run :delayed, so that
# they run at the end of the chef-client run, after the nova service have been
# restarted (in case of a config change and if we're also a controller)
execute "trigger-nova-own-az-config" do
  command "true"
end
