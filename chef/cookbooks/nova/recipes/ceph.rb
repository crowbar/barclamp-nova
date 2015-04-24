#
# Copyright (c) 2015 SUSE Linux GmbH.
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
# Cookbook Name:: nova
# Recipe:: ceph
#

has_internal = false
has_external = false

cinder_controller = search_env_filtered(:node, "roles:cinder-controller").first
return if cinder_controller.nil?

# First loop to find if we have internal/external cluster
cinder_controller[:cinder][:volumes].each_with_index do |volume, volid|
  next unless volume[:backend_driver] == "rbd"

  has_internal ||= true if volume[:rbd][:use_crowbar]
  has_external ||= true unless volume[:rbd][:use_crowbar]
end

if has_internal
  ceph_env_filter = " AND ceph_config_environment:ceph-config-default"
  ceph_servers = search(:node, "roles:ceph-osd#{ceph_env_filter}") || []
  if ceph_servers.length > 0
    include_recipe "ceph::keyring"
  else
    message = "Ceph was not deployed with Crowbar yet!"
    Chef::Log.fatal(message)
    raise message
  end
end

if has_external
  # Ensure ceph is available here
  if node[:platform] == "suse"
    # install package in compile phase because we will run "ceph -s"
    package "ceph-common" do
      action :nothing
    end.run_action(:install)
  end
end

# Second loop to do our setup
cinder_controller[:cinder][:volumes].each_with_index do |volume, volid|
  next unless volume[:backend_driver] == "rbd"

  if volume[:rbd][:use_crowbar]
    ceph_conf = "/etc/ceph/ceph.conf"
    admin_keyring = "/etc/ceph/ceph.client.admin.keyring"
  else
    ceph_conf = volume[:rbd][:config_file]
    admin_keyring = volume[:rbd][:admin_keyring]

    if ceph_conf.empty? || !File.exists?(ceph_conf)
      Chef::Log.info("Ceph configuration file is missing; skipping the ceph setup for backend #{volume[:backend_name]}")
      next
    end

    if !admin_keyring.empty? && File.exists?(admin_keyring)
      Chef::Log.info("Using external ceph cluster for cinder #{volume[:backend_name]} backend, with automatic setup.")
    else
      Chef::Log.info("Using external ceph cluster for cinder #{volume[:backend_name]} backend, with no automatic setup.")
      next
    end

    cmd = ["ceph", "-k", admin_keyring, "-c", ceph_conf, "-s"]
    check_ceph = Mixlib::ShellOut.new(cmd)

    unless check_ceph.run_command.stdout.match("(HEALTH_OK|HEALTH_WARN)")
      Chef::Log.info("Ceph cluster is not healthy; skipping the ceph setup for backend #{volume[:backend_name]}")
      next
    end
  end

  rbd_user = volume[:rbd][:user]
  rbd_uuid = volume[:rbd][:secret_uuid]

  secret_file_path = "/etc/ceph/ceph-secret-#{rbd_uuid}.xml"
  
  file secret_file_path do
    owner "root"
    group "root"
    mode "0640"
    content "<secret ephemeral='no' private='no'> <uuid>#{rbd_uuid}</uuid><usage type='ceph'> <name>client.#{rbd_user} secret</name> </usage> </secret>"
  end #file secret_file_path

  ruby_block "save nova key as libvirt secret" do
    block do
      # Check if libvirt is installed and started
      if system("virsh hostname &> /dev/null")

        # First remove conflicting secrets due to same usage name
        virsh_secret = Mixlib::ShellOut.new("virsh secret-list")
        secret_list = virsh_secret.run_command.stdout
        virsh_secret.error!

        secret_lines = secret_list.strip.split("\n")
        if secret_lines.length < 2 || !secret_lines[0].start_with?("UUID") || !secret_lines[1].start_with?("----")
          raise "cannot fetch list of libvirt secret"
        end
        secret_lines.shift(2)

        secret_lines.each do |secret_line|
          secret_uuid = secret_line.split(" ")[0]
          cmd = ["virsh", "secret-dumpxml", secret_uuid]
          virsh_secret_dumpxml = Mixlib::ShellOut.new(cmd)
          secret_xml = virsh_secret_dumpxml.run_command.stdout
          # some secrets might not be ceph-related, skip these
          next if secret_xml.index("<usage type='ceph'>").nil?

          # lazy xml parsing
          re_match = %r[<usage type='ceph'>.*<name>(.*)</name>]m.match(secret_xml)
          next if re_match.nil?
          secret_usage = re_match[1]
          undefine = false

          if secret_uuid == rbd_uuid
            undefine = true if secret_usage != "client.#{rbd_user} secret"
          else
            undefine = true if secret_usage == "client.#{rbd_user} secret"
          end

          if undefine
            cmd = ["virsh", "secret-undefine", secret_uuid]
            virsh_secret_undefine = Mixlib::ShellOut.new(cmd)
            virsh_secret_undefine.run_command
          end
        end

        # Now add our secret and its value
        cmd = ["ceph", "-k", admin_keyring, "-c", ceph_conf, "auth", "get-key", "client.#{rbd_user}" ]
        ceph_get_key = Mixlib::ShellOut.new(cmd)
        client_key = ceph_get_key.run_command.stdout
        ceph_get_key.error!

        cmd = ["virsh", "secret-get-value", rbd_uuid ]
        virsh_secret_get_value = Mixlib::ShellOut.new(cmd)
        secret = virsh_secret_get_value.run_command.stdout.chomp.strip

        if secret != client_key
          cmd = ["virsh", "secret-define", "--file", secret_file_path]
          virsh_secret_define = Mixlib::ShellOut.new(cmd)
          virsh_secret_define.run_command

          cmd = ["virsh", "secret-set-value", "--secret", rbd_uuid, "--base64", client_key]
          virsh_secret_set_value = Mixlib::ShellOut.new(cmd)
          virsh_secret_set_value.run_command
          virsh_secret_set_value.error!
        end
      end
    end
  end

end
