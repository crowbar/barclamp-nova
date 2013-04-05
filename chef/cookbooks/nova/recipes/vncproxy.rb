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

nova_path = "/opt/nova"
venv_path = node[:nova][:use_virtualenv] ? "#{nova_path}/.venv" : nil

if node.platform != "suse"
  pkgs=%w[python-numpy nova-console nova-consoleauth]
  pkgs=%w[python-numpy] if node[:nova][:use_gitrepo]
  pkgs.each do |pkg|
    package pkg do
      action :upgrade
      options "--force-yes"
    end
  end
end

# forcing novnc is deliberate on suse
unless node[:nova][:use_gitrepo]
  if node[:nova][:use_novnc] || node.platform == "suse"
    package "novnc" do
      package_name "openstack-novncproxy" if node.platform == "suse"
      action :upgrade
      options "--force-yes" if node.platform != "suse"
    end
    service "novnc" do
      service_name "openstack-novncproxy" if node.platform == "suse"
      supports :status => true, :restart => true
      action [:enable, :start]
      subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
    end
  else
    package "nova-vncproxy" do
      action :upgrade
      options "--force-yes"
    end
    execute "Fix permission Bug" do
      command "sed -i 's/nova$/root/g' /etc/init/nova-vncproxy.conf"
      action :run
    end
  
    service "nova-vncproxy" do
      supports :status => true, :restart => true
      action [:enable, :start]
      subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
    end
  end
  service "nova-consoleauth" do
    service_name "openstack-nova-consoleauth" if node.platform == "suse"
    supports :status => true, :restart => true
    action [:enable, :start]
    subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
  end
else
  nova_package "console" do
    virtualenv venv_path
  end
  nova_package "consoleauth" do
    virtualenv venv_path
  end
  unless node[:nova][:use_novnc]
    nova_package "xvpvncproxy" do
      virtualenv venv_path
    end
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
