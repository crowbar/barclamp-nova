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

nova_path = "/opt/nova"
quantum_path = "/opt/quantum"
venv_nova_path = node[:nova][:use_virtualenv] ? "#{nova_path}/.venv" : nil
venv_nova_prefix_path = node[:nova][:use_virtualenv] ? "#{venv_nova_path}/bin/activate && " : nil
venv_quantum_path = node[:nova][:use_virtualenv] ? "#{quantum_path}/.venv" : nil
venv_quantum_prefix_path = node[:nova][:use_virtualenv] ? "#{venv_quantum_path}/bin/activate && " : nil
unless node[:nova][:use_gitrepo]
  package "quantum-server" do
    action :install
  end
else
  quantum_servers = search(:node, "roles:quantum-server") || []
  quantum_node = nil
  if quantum_servers.length > 0
    quantum_node = quantum_servers[0]
  else
    quantum_node = node
  end

  pfs_and_install_deps "quantum" do
    virtualenv venv_quantum_path
    path quantum_path
    cookbook "quantum"
    wrap_bins [ "quantum", "quantum-rootwrap" ]
    cnode quantum_node
  end

  link_service "quantum-plugin-openvswitch-agent" do
    bin_name "quantum-openvswitch-agent --config-dir /etc/quantum/"
    virtualenv venv_quantum_path
  end
  create_user_and_dirs("quantum")
  execute "quantum_cp_policy.json" do
    command "cp /opt/quantum/etc/policy.json /etc/quantum/"
    creates "/etc/quantum/policy.json"
  end
  execute "quantum_cp_rootwrap" do
    command "cp -r /opt/quantum/etc/quantum/rootwrap.d /etc/quantum/rootwrap.d"
    creates "/etc/quantum/rootwrap.d"
  end
  cookbook_file "/etc/quantum/rootwrap.conf" do
    source "quantum-rootwrap.conf" 
    mode 00644
    owner "quantum"
  end
end

template "/etc/sudoers.d/quantum-rootwrap" do
  source "quantum-rootwrap.erb"
  mode 0440
  variables(:user => "quantum")
end

kern_release=(`uname -r`).strip
package "linux-headers-#{kern_release}" do
    action :install
end
package "openvswitch-switch" do
    action :install
end
package "openvswitch-datapath-dkms" do
    action :install
end

service "openvswitch-switch" do
  supports :status => true, :restart => true
  action :enable
end
service "quantum-plugin-openvswitch-agent" do
  supports :status => true, :restart => true
  action :enable
end

Chef::Log.info("Configuring Quantum to use MySQL backend")

include_recipe "mysql::client"

package "python-mysqldb" do
    action :install
end

quantum_servers = search(:node, "roles:quantum-server") || []
if quantum_servers.length > 0
  quantum_node=quantum_servers[0]
else
  quantum_node=node
end


env_filter = " AND mysql_config_environment:mysql-config-#{quantum_node[:quantum][:mysql_instance]}"
mysqls = search(:node, "roles:mysql-server#{env_filter}") || []
if mysqls.length > 0
    mysql = mysqls[0]
    mysql = node if mysql.name == node.name
else
    mysql = node
end

mysql_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(mysql, "admin").address if mysql_address.nil?
Chef::Log.info("Mysql server found at #{mysql_address}")


ovs_sql_connection = "mysql://#{quantum_node[:quantum][:db][:ovs_user]}:#{quantum_node[:quantum][:db][:ovs_password]}@#{mysql_address}/#{quantum_node[:quantum][:db][:ovs_database]}"
sql_connection = "mysql://#{quantum_node[:quantum][:db][:user]}:#{quantum_node[:quantum][:db][:password]}@#{mysql_address}/#{quantum_node[:quantum][:db][:database]}"


env_filter = " AND rabbitmq_config_environment:rabbitmq-config-#{node[:nova][:rabbitmq_instance]}"
rabbits = search(:node, "roles:rabbitmq-server#{env_filter}") || []
if rabbits.length > 0
  rabbit = rabbits[0]
  rabbit = node if rabbit.name == node.name
else
  rabbit = node
end
rabbit_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(rabbit, "admin").address
Chef::Log.info("Rabbit server found at #{rabbit_address}")
if rabbit[:nova]
  #agordeev:
  # rabbit settings will work only after nova proposal be deployed
  # and cinder services will be restarted then
  rabbit_settings = {
    :address => rabbit_address,
    :port => rabbit[:rabbitmq][:port],
    :user => rabbit[:rabbitmq][:user],
    :password => rabbit[:rabbitmq][:password],
    :vhost => rabbit[:rabbitmq][:vhost]
  }
else
  rabbit_settings = nil
end

#per_tenant_vlan=node[:nova][:network][:tenant_vlans] rescue false
if quantum_node[:quantum][:networking_mode] != 'local'
  per_tenant_vlan=true
else
  per_tenant_vlan=false
end
quantum_networking_mode = quantum_node[:quantum][:networking_mode]


fixed_net=node[:network][:networks]["nova_fixed"]
flat_network_bridge = fixed_net["use_vlan"] ? "br#{fixed_net["vlan"]}" : "br#{fixed_interface}"
vlan_start=fixed_net["vlan"]
vlan_end=vlan_start+2000


template "/etc/quantum/quantum.conf" do
    source "quantum.conf.erb"
    mode "0644"
    owner "quantum"
    variables(
      :sql_connection => sql_connection,
      :sql_idle_timeout => quantum_node[:quantum][:sql][:idle_timeout],
      :sql_min_pool_size => quantum_node[:quantum][:sql][:min_pool_size],
      :sql_max_pool_size => quantum_node[:quantum][:sql][:max_pool_size],
      :sql_pool_timeout => quantum_node[:quantum][:sql][:pool_timeout],
      :debug => quantum_node[:quantum][:debug],
      :verbose => quantum_node[:quantum][:verbose],
      :admin_token => quantum_node[:quantum][:service][:token],
      :service_port => quantum_node[:quantum][:api][:service_port], # Compute port
      :service_host => quantum_node[:quantum][:api][:service_host],
      :use_syslog => quantum_node[:quantum][:use_syslog],
      :rabbit_settings => rabbit_settings,
      :per_tenant_vlan => per_tenant_vlan,
      :vlan_start => vlan_start,
      :vlan_end => vlan_end,
      :networking_mode => quantum_networking_mode
    )
    notifies :restart, resources(:service => "quantum-plugin-openvswitch-agent"), :immediately
end

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

