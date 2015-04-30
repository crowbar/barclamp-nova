# Copyright 2011, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
define :nova_package, :enable => true, :use_pacemaker_provider => false do

  nova_name="nova-#{params[:name]}"

  package nova_name do
    package_name "openstack-#{nova_name}" if %w(redhat centos suse).include?(node.platform)
    action :install
  end

  service nova_name do
    service_name "openstack-#{nova_name}" if %w(redhat centos suse).include?(node.platform)
    if (platform?("ubuntu") && node.platform_version.to_f >= 10.04)
      restart_command "stop #{nova_name} ; start #{nova_name}"
      stop_command "stop #{nova_name}"
      start_command "start #{nova_name}"
      status_command "status #{nova_name} | cut -d' ' -f2 | cut -d'/' -f1 | grep start"
    end
    supports :status => true, :restart => true

    if params[:enable] != false
      # only enable and start the service, unless a reboot has been triggered
      # (e.g. because of switching from # kernel-default to kernel-xen)
      unless node.run_state[:reboot]
        action [:enable, :start]
      else
        # start will happen after reboot, and potentially even fail before
        # reboot (ie. on installing kernel-xen + expecting libvirt to already
        # use xen before)
        unless %w(redhat centos).include?(node.platform)
          action [:enable]
        else
          #needed until https://bugs.launchpad.net/oslo/+bug/1177184 is solved
          action [:enable, :start]
        end
      end
    end

    subscribes :restart, resources(:template => "/etc/nova/nova.conf")

    provider Chef::Provider::CrowbarPacemakerService if params[:use_pacemaker_provider]
  end

end
