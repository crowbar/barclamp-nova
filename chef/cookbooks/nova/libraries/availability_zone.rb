#
# Copyright 2014, SUSE
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

module NovaAvailabilityZone
  def self.fetch_set_az_command_no_arg(node, cookbook_name)
    keystone_settings = KeystoneHelper.keystone_settings(node, cookbook_name)

    nova_insecure = node[:nova][:ssl][:enabled] && node[:nova][:ssl][:insecure]

    command = [ "/usr/bin/crowbar-nova-set-availability-zone" ]
    command << "--os-username"
    command << keystone_settings['admin_user']
    command << "--os-password"
    command << keystone_settings['admin_password']
    command << "--os-tenant-name"
    command << keystone_settings['default_tenant']
    command << "--os-auth-url"
    command << KeystoneHelper.versioned_service_URL(keystone_settings["protocol"],
                                                    keystone_settings["internal_url_host"],
                                                    keystone_settings["service_port"],
                                                    "2.0")
    command << "--os-region-name"
    command << keystone_settings['endpoint_region']

    if keystone_settings['insecure'] || nova_insecure
      command << "--insecure"
    end

    command
  end

  def self.add_arg_to_set_az_command(command_no_arg, compute_node)
    availability_zone = ""
    unless compute_node[:crowbar_wall].nil? or compute_node[:crowbar_wall][:openstack].nil?
      availability_zone = compute_node[:crowbar_wall][:openstack][:availability_zone]
    end

    command = command_no_arg.clone
    command << compute_node.hostname
    # we need an array for the command to avoid command injection with this part
    command << availability_zone

    # Note: if availability_zone is "", then the command will move the host to
    # the default availability zone, which is what we want

    command
  end
end
