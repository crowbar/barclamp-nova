# Copyright 2013 Dell, Inc.
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

include_recipe "quantum::common_install"

fip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "nova_fixed")
if fip
  fixed_address = fip.address
  fixed_mask = fip.netmask
  fixed_interface = fip.interface
  fixed_interface = "#{fip.interface}.#{fip.vlan}" if fip.use_vlan
else
  fixed_interface = nil
end
pip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "public")
if pip
  public_address = pip.address
  public_mask = pip.netmask
  public_interface = pip.interface
  public_interface = "#{pip.interface}.#{pip.vlan}" if pip.use_vlan
else
  public_interface = nil
end

fixed_net=node[:network][:networks]["nova_fixed"]
flat_network_bridge = fixed_net["use_vlan"] ? "br#{fixed_net["vlan"]}" : "br#{fixed_interface}"

execute "create_int_br" do
  command "ovs-vsctl add-br br-int"
  not_if "ovs-vsctl list-br | grep -q br-int"
end
execute "create_fixed_br" do
  command "ovs-vsctl add-br br-fixed"
  not_if "ovs-vsctl list-br | grep -q br-fixed"
end
#execute "create_public_br" do
#  command "ovs-vsctl add-br br-public"
#  not_if "ovs-vsctl list-br | grep -q br-public"
#end
execute "add_fixed_port" do
  command "ovs-vsctl del-port br-fixed #{flat_network_bridge} ; ovs-vsctl add-port br-fixed #{flat_network_bridge}"
  not_if "ovs-dpctl show system@br-fixed | grep -q #{flat_network_bridge}"
end
#execute "add_public_port" do
#  command "ovs-vsctl add-port br-public #{public_interface}"
#  not_if "ovs-vsctl list-ports br-public | grep -q #{public_interface}"
#end
#execute "move_fixed_ip" do
#  command "ip address flush dev #{fixed_interface} ; ip address flush dev #{flat_network_bridge} ; ifconfig br-fixed #{fixed_address} netmask #{fixed_mask}"
#  not_if "ip addr show br-fixed | grep -q #{fixed_address}"
#end
#execute "move_public_ip" do
#  command "ip address flush dev #{public_interface} ; ifconfig br-public #{public_address} netmask #{public_mask}"
#  not_if "ip addr show br-public | grep -q #{public_address}"
#end

