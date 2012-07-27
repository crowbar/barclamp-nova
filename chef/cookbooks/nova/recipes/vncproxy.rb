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

if node.platform == "suse"
    pkgs=%w[openstack-novncproxy]
else
    pkgs=%w[python-numpy nova-vncproxy nova-console nova-consoleauth]
end

pkgs.each do |pkg|
  package pkg do
    action :upgrade
    options "--force-yes" if node.platform != "suse"
  end
end

if node.platform != "suse"
  execute "Fix permission Bug" do
    command "sed -i 's/nova$/root/g' /etc/init/nova-vncproxy.conf"
    action :run
  end
end

if node.platform == "suse"
  ssl_enabled = node[:nova][:novnc][:ssl_enabled] ? 'yes':'no'
  ssl_cert = node[:nova][:novnc][:ssl_crt_file] || ''
  ssl_key  = node[:nova][:novnc][:ssl_key_file] || ''
  ssl_cert = node[:nova][:apache][:ssl_crt_file] if ssl_cert == ''
  ssl_key  = node[:nova][:apache][:ssl_key_file] if ssl_key  == ''

  execute "Write sysconfig for openstack-novncproxy" do
    command 'scnovnc=/etc/sysconfig/openstack-novncproxy
if grep -q "^\s*NOVNC_SSL_ENABLE" $scnovnc 2>/dev/null ; then
  sed -i -e "s#^\s*NOVNC_SSL_ENABLE.*#NOVNC_SSL_ENABLE=\"' + ssl_enabled + '\"#" $scnovnc
else
  echo NOVNC_SSL_ENABLE=\"' + ssl_enabled + '\" >> $scnovnc
fi
if grep -q "^\s*NOVNC_SSL_CERT" $scnovnc 2>/dev/null ; then
  sed -i -e "s#^\s*NOVNC_SSL_CERT.*#NOVNC_SSL_CERT=\"' + ssl_cert + '\"#" $scnovnc
else
  echo NOVNC_SSL_CERT=\"' + ssl_cert + '\" >> $scnovnc
fi
if grep -q "^\s*NOVNC_SSL_KEY" $scnovnc 2>/dev/null ; then
  sed -i -e "s#^\s*NOVNC_SSL_KEY.*#NOVNC_SSL_KEY=\"' + ssl_key + '\"#" $scnovnc
else
  echo NOVNC_SSL_KEY=\"' + ssl_key + '\" >> $scnovnc
fi'
    action :run
  end
end

service "nova-vncproxy" do
  service_name "openstack-novncproxy" if node.platform == "suse"
  supports :status => true, :restart => true
  action :enable
  subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
end

service "nova-consoleauth" do
  service_name "openstack-nova-consoleauth" if node.platform == "suse"
  supports :status => true, :restart => true
  action :enable
  subscribes :restart, resources(:template => "/etc/nova/nova.conf"), :delayed
end
