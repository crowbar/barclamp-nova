#
# Cookbook Name:: nova
# Recipe:: vncproxy
#
# Copyright 2009, Example Com
# Copyright 2011, Dell Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "nova::config"

unless %w(redhat centos suse).include?(node.platform)
  pkgs=%w[python-numpy nova-console nova-consoleauth]
  pkgs=%w[python-numpy] if node[:nova][:use_gitrepo]
  pkgs.each do |pkg|
    package pkg do
      action :install
      options "--force-yes"
    end
  end
end

# forcing novnc is deliberate on suse
unless node[:nova][:use_gitrepo]
  if node[:nova][:use_novnc]
    if %w(redhat centos suse).include?(node.platform)
      package "openstack-nova-novncproxy" do
        action :install
      end
      unless %w(redhat centos).include?(node.platform)
        package "openstack-nova-consoleauth" do
          action :install
        end
      end
    else
      package "nova-novncproxy" do
        action :install
        options "--force-yes"
      end
      execute "Fix permission Bug" do
        command "sed -i 's/nova$/root/g' /etc/init/nova-novncproxy.conf"
        action :run
      end
    end
    service "nova-novncproxy" do
      service_name "openstack-nova-novncproxy" if %w(redhat centos suse).include?(node.platform)
      supports :status => true, :restart => true
      action [:enable, :start]
      subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
    end
  end
  service "nova-consoleauth" do
    service_name "openstack-nova-consoleauth" if %w(redhat centos suse).include?(node.platform)
    supports :status => true, :restart => true
    action [:enable, :start]
    subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
  end
  # This does not appear to exist for Folsom anymore.
  # service "novnc" do
  #  supports :status => true, :restart => true
  #  action [:enable, :start]
  #  subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
  # end
else
  nova_package("console")
  nova_package("consoleauth")
  unless node[:nova][:use_novnc]
    nova_package("xvpvncproxy")
  else
    novnc_service = "nova-novncproxy"
    #agordeev: remove hardcoded paths
    novnc_path = "/opt/novnc"
    nova_path = "/opt/nova"
    pfs_and_install_deps "novnc" do
      reference "master"
      without_setup true
    end
    [
      "/usr/lib/novnc",
      "/usr/share/novnc",
      "/usr/share/novnc/utils",
      "/usr/share/novnc/include",
      "/usr/share/doc/novnc"
      ].map { |d| directory(d) }
    execute "build_rebind" do
      cwd "#{novnc_path}/utils"
      command "make"
      creates "#{novnc_path}/utils/rebind.so"
    end
    bash "copy_and_install" do
      cwd novnc_path
      code <<-EOH
        while read line
        do
          eval "cp -f $line"
        done < debian/novnc.install
        cp utils/rebind /usr/bin/
        cp utils/rebind.o /usr/lib/novnc
        cp utils/rebind.so /usr/lib/novnc
        cp #{nova_path}/bin/#{novnc_service} utils/#{novnc_service}
        chmod 755 /usr/bin/rebind
        chmod 644 /usr/lib/novnc/rebind.*
        chmod -R a+r /usr/share/novnc/*
        chmod -R a+r /usr/share/doc/novnc/
      EOH
      not_if { File.exists?("/usr/share/novnc/utils/rebind.c") }
    end
    link_service novnc_service do
      user node[:nova][:user]
      opt_params "--web /usr/share/novnc"
      opt_path "#{novnc_path}/utils"
    end
    service novnc_service do
      supports :status => true, :restart => true
      action [:enable, :start]
      subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
    end
  end
end
