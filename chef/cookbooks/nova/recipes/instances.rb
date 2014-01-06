#
# Cookbook Name:: nova
# Recipe:: instances
#
# Copyright 2013, SUSE Linux Products GmbH
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

if node[:nova]["use_shared_instance_storage"]

  package "nfs-kernel-server"

  service "nfs-kernel-server" do
    service_name "nfs" if node[:platform] =~ /^(redhat|centos)$/
    service_name "nfsserver" if node[:platform] == "suse"
    supports :restart => true, :status => true, :reload => true
    running true
    enabled true
    action [ :enable, :start ]
  end

  admin_net = node[:network][:networks][:admin]

  template "/etc/exports" do
    source "exports.erb"
    group "root"
    owner "root"
    mode 0644
    variables(
      :admin_subnet => admin_net[:subnet]  + "/" + admin_net[:netmask],
      :instances_path => node[:nova][:instances_path]
    )
    notifies :run, "execute[nfs-export]", :delayed
  end

  execute "nfs-export" do
    command "exportfs -a"
    action :nothing
  end
end
