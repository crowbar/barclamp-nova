#
# Cookbook Name:: nova
# Recipe:: network
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

include_recipe "nova::config" 

if node[:nova][:networking_backend]=="nova-network"
  nova_package("network")
end

# Crowbar uses the network node as the gateway in flat non-dhcp modes, add the
# firewall rule for UEC images to be able to fetch metadata info
unless node[:nova][:network][:dhcp_enabled]
  execute "iptables -t nat -A PREROUTING -d 169.254.169.254/32 -p tcp -m tcp --dport 80 -j DNAT --to-destination #{node[:nova][:my_ip]}:8773"
end

# To make floating ip works, turn on routing.
bash "turn on routing" do
  code <<-'EOH'
sysctl -w net.ipv4.conf.all.forwarding=1
sysctl -w net.ipv4.conf.all.rp_filter=0
EOH
end

if node.platform != "suse"
  file "/etc/sysctl.d/50-iprouting" do
    owner "root"
    group "root"
    mode "0644"
    action :create
  end
else
  ruby_block "edit sysconfig sysctl" do
    block do
      rc = Chef::Util::FileEdit.new("/etc/sysconfig/sysctl")
      rc.search_file_replace_line(/^IP_FORWARD=/, 'IP_FORWARD="yes"')
      rc.write_file
    end
  end
  ruby_block "edit sysctl.conf" do
    block do
      rc = Chef::Util::FileEdit.new("/etc/sysctl.conf")
      rc.search_file_replace_line(/^net.ipv4.conf.all.rp_filter/, 'net.ipv4.conf.all.rp_filter = 0')
      rc.write_file
    end
  end
end
