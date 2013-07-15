#
# Cookbook Name:: nova
# Recipe:: config
#
# Copyright 2010, 2011 Opscode, Inc.
# Copyright 2011 Dell, Inc.
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

node.set[:nova][:my_ip] = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address

nova_path = "/opt/nova"
venv_path = node[:nova][:use_virtualenv] ? "#{nova_path}/.venv" : nil
venv_prefix_path = node[:nova][:use_virtualenv] ? ". #{venv_path}/bin/activate && " : nil

unless node[:nova][:use_gitrepo]
  package "nova-common" do
    if node.platform == "suse"
      package_name "openstack-nova"
    else
      options "--force-yes -o Dpkg::Options::=\"--force-confdef\""
    end
    action :install
  end

  # nova.conf.erb has notification_driver=ceilometer.compute.nova_notifier, thus:
  package "python-ceilometerclient"
else
  pfs_and_install_deps "nova" do
    virtualenv venv_path
    wrap_bins(["nova-rootwrap", "nova", "nova-manage"])
  end
end

include_recipe "database::client"

env_filter = " AND database_config_environment:database-config-#{node[:nova][:db][:database_instance]}"
sqls = search(:node, "roles:database-server#{env_filter}") || []
if sqls.length > 0
  sql = sqls[0]
  sql = node if sql.name == node.name
else
  sql = node
end
backend_name = Chef::Recipe::Database::Util.get_backend_name(sql)

include_recipe "#{backend_name}::client"
include_recipe "#{backend_name}::python-client"

database_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(sql, "admin").address if database_address.nil?
Chef::Log.info("database server found at #{database_address}")
database_connection = "#{backend_name}://#{node[:nova][:db][:user]}:#{node[:nova][:db][:password]}@#{database_address}/#{node[:nova][:db][:database]}"

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
rabbit_settings = {
  :address => rabbit_address,
  :port => rabbit[:rabbitmq][:port],
  :user => rabbit[:rabbitmq][:user],
  :password => rabbit[:rabbitmq][:password],
  :vhost => rabbit[:rabbitmq][:vhost]
}

apis = search(:node, "recipes:nova\\:\\:api#{env_filter}") || []
if apis.length > 0 and !node[:nova][:network][:ha_enabled]
  api = apis[0]
  api = node if api.name == node.name
else
  api = node
end
admin_api_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(api, "admin").address
admin_api_host = api[:fqdn]
# For the public endpoint, we prefer the public name. If not set, then we
# use the IP address except for SSL, where we always prefer a hostname
# (for certificate validation).
public_api_host = api[:crowbar][:public_name]
if public_api_host.nil? or public_api_host.empty?
  unless api[:nova][:ssl][:enabled]
    public_api_host = Chef::Recipe::Barclamp::Inventory.get_network_by_type(api, "public").address
  else
    public_api_host = 'public.'+api[:fqdn]
  end
end
Chef::Log.info("Api server found at #{admin_api_host} #{public_api_host}")

dns_servers = search(:node, "roles:dns-server") || []
if dns_servers.length > 0
  dns_server = dns_servers[0]
  dns_server = node if dns_server.name == node.name
else
  dns_server = node
end
dns_server_public_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(dns_server, "public").address
Chef::Log.info("DNS server found at #{dns_server_public_ip}")

glance_servers = search(:node, "roles:glance-server") || []
if glance_servers.length > 0
  glance_server = glance_servers[0]
  glance_server = node if glance_server.name == node.name
  glance_server_host = glance_server[:fqdn]
  glance_server_port = glance_server[:glance][:api][:bind_port]
  glance_server_protocol = glance_server[:glance][:api][:protocol]
  glance_server_insecure = glance_server_protocol == 'https' && glance_server[:glance][:ssl][:insecure]
else
  glance_server_host = nil
  glance_server_port = nil
  glance_server_protocol = nil
  glance_server_insecure = nil
end
Chef::Log.info("Glance server at #{glance_server_host}")

vncproxies = search(:node, "recipes:nova\\:\\:vncproxy#{env_filter}") || []
if vncproxies.length > 0
  vncproxy = vncproxies[0]
  vncproxy = node if vncproxy.name == node.name
else
  vncproxy = node
end
# For the public endpoint, we prefer the public name. If not set, then we
# use the IP address except for SSL, where we always prefer a hostname
# (for certificate validation).
vncproxy_public_host = vncproxy[:crowbar][:public_name]
if vncproxy_public_host.nil? or vncproxy_public_host.empty?
  unless vncproxy[:nova][:novnc][:ssl][:enabled]
    vncproxy_public_host = Chef::Recipe::Barclamp::Inventory.get_network_by_type(vncproxy, "public").address
  else
    vncproxy_public_host = 'public.'+vncproxy[:fqdn]
  end
end
Chef::Log.info("VNCProxy server at #{vncproxy_public_host}")

cookbook_file "/etc/default/nova-common" do
  source "nova-common"
  owner node[:nova][:user]
  group "root"
  mode 0640
  action :nothing
end

def mask_to_bits(mask)
  octets = mask.split(".")
  count = 0
  octets.each do |octet|
    break if octet == "0"
    c = 1 if octet == "128"
    c = 2 if octet == "192"
    c = 3 if octet == "224"
    c = 4 if octet == "240"
    c = 5 if octet == "248"
    c = 6 if octet == "252"
    c = 7 if octet == "254"
    c = 8 if octet == "255"
    count = count + c
  end

  count
end

# build the public_interface for the fixed net
public_net = node["network"]["networks"]["public"]
fixed_net = node["network"]["networks"]["nova_fixed"]
nova_floating = node[:network][:networks]["nova_floating"]

node.set[:nova][:network][:fixed_range] = "#{fixed_net["subnet"]}/#{mask_to_bits(fixed_net["netmask"])}"
node.set[:nova][:network][:floating_range] = "#{nova_floating["subnet"]}/#{mask_to_bits(nova_floating["netmask"])}"

fip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "nova_fixed")
if fip
  fixed_interface = fip.interface
  fixed_interface = "#{fip.interface}.#{fip.vlan}" if fip.use_vlan
else
  fixed_interface = nil
end
pip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "public")
if pip
  public_interface = pip.interface
  public_interface = "#{pip.interface}.#{pip.vlan}" if pip.use_vlan
else
  public_interface = nil
end

flat_network_bridge = fixed_net["use_vlan"] ? "br#{fixed_net["vlan"]}" : "br#{fixed_interface}"

node.set[:nova][:network][:public_interface] = public_interface
if !node[:nova][:network][:dhcp_enabled]
  node.set[:nova][:network][:flat_network_bridge] = flat_network_bridge
  node.set[:nova][:network][:flat_interface] = fixed_interface
elsif !node[:nova][:network][:tenant_vlans]
  node.set[:nova][:network][:flat_network_bridge] = flat_network_bridge
  node.set[:nova][:network][:flat_network_dhcp_start] = fixed_net["ranges"]["dhcp"]["start"]
  node.set[:nova][:network][:flat_interface] = fixed_interface
else
  node.set[:nova][:network][:vlan_interface] = fip.interface rescue nil
  node.set[:nova][:network][:vlan_start] = fixed_net["vlan"]
end

if node[:nova][:use_gitrepo]
  package("libvirt-bin")
  create_user_and_dirs "nova" do
    opt_dirs ["/var/lib/nova/instances"]
    user_gid "libvirtd"
  end

  execute "cp_policy.json" do
    command "cp #{nova_path}/etc/nova/policy.json /etc/nova/"
    creates "/etc/nova/policy.json"
  end
  
  template "/etc/sudoers.d/nova-rootwrap" do
    source "nova-rootwrap.erb"
    mode 0440
    variables(:user => node[:nova][:user])
  end

  bash "deploy_filters" do
    cwd nova_path
    code <<-EOH
    ### that was copied from devstack's stack.sh
    if [[ -d $NOVA_DIR/etc/nova/rootwrap.d ]]; then
      # Wipe any existing rootwrap.d files first
      if [[ -d $NOVA_CONF_DIR/rootwrap.d ]]; then
          rm -rf $NOVA_CONF_DIR/rootwrap.d
      fi
      # Deploy filters to /etc/nova/rootwrap.d
      mkdir -m 755 $NOVA_CONF_DIR/rootwrap.d
      cp $NOVA_DIR/etc/nova/rootwrap.d/*.filters $NOVA_CONF_DIR/rootwrap.d
      chown -R root:root $NOVA_CONF_DIR/rootwrap.d
      chmod 644 $NOVA_CONF_DIR/rootwrap.d/*
      # Set up rootwrap.conf, pointing to /etc/nova/rootwrap.d
      cp $NOVA_DIR/etc/nova/rootwrap.conf $NOVA_CONF_DIR/
      sed -e "s:^filters_path=.*$:filters_path=$NOVA_CONF_DIR/rootwrap.d:" -i $NOVA_CONF_DIR/rootwrap.conf
      chown root:root $NOVA_CONF_DIR/rootwrap.conf
      chmod 0644 $NOVA_CONF_DIR/rootwrap.conf
    fi
    ### end
  EOH
  environment({
    'NOVA_DIR' => nova_path,
    'NOVA_CONF_DIR' => '/etc/nova',
  })
  not_if {File.exists?("/etc/nova/rootwrap.d")}
  end
end

env_filter = " AND keystone_config_environment:keystone-config-#{node[:nova][:keystone_instance]}"
keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
if keystones.length > 0
  keystone = keystones[0]
  keystone = node if keystone.name == node.name
else
  keystone = node
end

keystone_host = keystone[:fqdn]
keystone_protocol = keystone["keystone"]["api"]["protocol"]
keystone_token = keystone["keystone"]["service"]["token"]
keystone_service_port = keystone["keystone"]["api"]["service_port"]
keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
keystone_service_user = node[:nova][:service_user]
keystone_service_password = node[:nova][:service_password]
Chef::Log.info("Keystone server found at #{keystone_host}")

cinder_servers = search(:node, "roles:cinder-controller") || []
if cinder_servers.length > 0
  cinder_server = cinder_servers[0]
  cinder_insecure = cinder_server[:cinder][:api][:protocol] == 'https' && cinder[:cinder][:ssl][:insecure]
else
  cinder_insecure = false
end

quantum_servers = search(:node, "roles:quantum-server") || []
if quantum_servers.length > 0
  quantum_server = quantum_servers[0]
  quantum_server = node if quantum_server.name == node.name
  quantum_protocol = quantum_server[:quantum][:api][:protocol]
  quantum_server_host = quantum_server[:fqdn]
  quantum_server_port = quantum_server[:quantum][:api][:service_port]
  quantum_insecure = quantum_protocol == 'https' && quantum_server[:quantum][:ssl][:insecure]
  quantum_service_user = quantum_server[:quantum][:service_user]
  quantum_service_password = quantum_server[:quantum][:service_password]
  if quantum_server[:quantum][:networking_mode] != 'local'
    per_tenant_vlan=true
  else
    per_tenant_vlan=false
  end
  quantum_networking_plugin = quantum_server[:quantum][:networking_plugin]
  quantum_networking_mode = quantum_server[:quantum][:networking_mode]
else
  quantum_server_host = nil
  quantum_server_port = nil
  quantum_service_user = nil
  quantum_service_password = nil
end
Chef::Log.info("Quantum server at #{quantum_server_host}")

env_filter = " AND inteltxt_config_environment:inteltxt-config-#{node[:nova][:itxt_instance]}"
oat_servers = search(:node, "roles:oat-server#{env_filter}") || []
if oat_servers.length > 0
  has_itxt = true
  oat_server = oat_servers[0]
  execute "fill_cert" do
    command <<-EOF
      echo | openssl s_client -connect "#{oat_server[:hostname]}:8443" -cipher DHE-RSA-AES256-SHA > /etc/nova/oat_certfile.cer || rm -fv /etc/nova/oat_certfile.cer
    EOF
    not_if { File.exists? "/etc/nova/oat_certfile.cer" }
  end
else
  has_itxt = false
  oat_server = node
end


directory "/var/lock/nova" do
  action :create
  owner node[:nova][:user]
  group "root"
end

if api == node and api[:nova][:ssl][:enabled]
  unless ::File.exists? api[:nova][:ssl][:certfile]
    message = "Certificate \"#{api[:nova][:ssl][:certfile]}\" is not present."
    Chef::Log.fatal(message)
    raise message
  end
  # we do not check for existence of keyfile, as the private key is allowed to
  # be in the certfile
  if api[:nova][:ssl][:cert_required] and !::File.exists? api[:nova][:ssl][:ca_certs]
    message = "Certificate CA \"#{api[:nova][:ssl][:ca_certs]}\" is not present."
    Chef::Log.fatal(message)
    raise message
  end
end

# if there's no certificate for novnc, use the ones from nova-api
if api[:nova][:novnc][:ssl][:enabled]
  unless api[:nova][:novnc][:ssl][:certfile].empty?
    api_novnc_ssl_certfile = api[:nova][:novnc][:ssl][:certfile]
    api_novnc_ssl_keyfile = api[:nova][:novnc][:ssl][:keyfile]
  else
    api_novnc_ssl_certfile = api[:nova][:ssl][:certfile]
    api_novnc_ssl_keyfile = api[:nova][:ssl][:keyfile]
  end
else
  api_novnc_ssl_certfile = ''
  api_novnc_ssl_keyfile = ''
end

if api == node and api[:nova][:novnc][:ssl][:enabled]
  unless ::File.exists? api_novnc_ssl_certfile
    message = "Certificate \"#{api_novnc_ssl_certfile}\" is not present."
    Chef::Log.fatal(message)
    raise message
  end
end

template "/etc/nova/nova.conf" do
  source "nova.conf.erb"
  owner node[:nova][:user]
  group "root"
  mode 0640
  variables(
            :dhcpbridge => "#{node[:nova][:use_gitrepo] ? nova_path:"/usr"}/bin/nova-dhcpbridge",
            :database_connection => database_connection,
            :rabbit_settings => rabbit_settings,
            :libvirt_type => node[:nova][:libvirt_type],
            :ec2_host => admin_api_host,
            :ec2_dmz_host => public_api_host,
            :dns_server_public_ip => dns_server_public_ip,
            :glance_server_protocol => glance_server_protocol,
            :glance_server_host => glance_server_host,
            :glance_server_port => glance_server_port,
            :glance_server_insecure => glance_server_insecure,
            :metadata_bind_address => admin_api_ip,
            :vncproxy_public_host => vncproxy_public_host,
            :vncproxy_ssl_enabled => api[:nova][:novnc][:ssl][:enabled],
            :vncproxy_cert_file => api_novnc_ssl_certfile,
            :vncproxy_key_file => api_novnc_ssl_keyfile,
            :quantum_protocol => quantum_protocol,
            :quantum_server_host => quantum_server_host,
            :quantum_server_port => quantum_server_port,
            :quantum_insecure => quantum_insecure,
            :quantum_service_user => quantum_service_user,
            :quantum_service_password => quantum_service_password,
            :quantum_networking_plugin => quantum_networking_plugin,
            :keystone_service_tenant => keystone_service_tenant,
            :keystone_protocol => keystone_protocol,
            :keystone_host => keystone_host,
            :keystone_admin_port => keystone_admin_port,
            :cinder_insecure => cinder_insecure,
            :ssl_enabled => api[:nova][:ssl][:enabled],
            :ssl_cert_file => api[:nova][:ssl][:certfile],
            :ssl_key_file => api[:nova][:ssl][:keyfile],
            :ssl_cert_required => api[:nova][:ssl][:cert_required],
            :ssl_ca_file => api[:nova][:ssl][:ca_certs],
            :oat_appraiser_host => oat_server[:hostname],
            :oat_appraiser_port => "8443",
            :has_itxt => has_itxt
            )
end

