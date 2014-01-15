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
