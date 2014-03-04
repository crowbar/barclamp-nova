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


unless node[:nova][:use_gitrepo]
  package "nova-common" do
    if %w(redhat centos suse).include?(node.platform)
      package_name "openstack-nova"
    else
      options "--force-yes -o Dpkg::Options::=\"--force-confdef\""
    end
    action :install
  end

else
  nova_path = "/opt/nova"
  venv_path = node[:nova][:use_virtualenv] ? "#{nova_path}/.venv" : nil
  venv_prefix_path = node[:nova][:use_virtualenv] ? ". #{venv_path}/bin/activate && " : nil

  pfs_and_install_deps "nova" do
    virtualenv venv_path
    # enable access to system site packages only for this virtualenv
    system_site true
    wrap_bins(["nova-rootwrap", "nova", "nova-manage"])
  end
end

include_recipe "database::client"

sqls = search_env_filtered(:node, "roles:database-server")
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
db_conn_scheme = backend_name
if node[:platform] == "suse" && backend_name == "mysql"
  # The C-extensions (python-mysql) can't be monkey-patched by eventlet. Therefore, when only one nova-conductor is present,
  # all DB queries are serialized. By using the pure-Python driver by default, eventlet can do it's job:
  db_conn_scheme = "mysql+pymysql"
end
database_connection = "#{db_conn_scheme}://#{node[:nova][:db][:user]}:#{node[:nova][:db][:password]}@#{database_address}/#{node[:nova][:db][:database]}"

rabbits = search_env_filtered(:node, "roles:rabbitmq-server")
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

apis = search_env_filtered(:node, "recipes:nova\\:\\:api")
if apis.length > 0
  api = apis[0]
  api = node if api.name == node.name
else
  api = node
end

api_ha_enabled = api[:nova][:ha][:enabled]
admin_api_host = CrowbarHelper.get_host_for_admin_url(api, api_ha_enabled)
public_api_host = CrowbarHelper.get_host_for_public_url(api, api[:nova][:ssl][:enabled], api_ha_enabled)
Chef::Log.info("Api server found at #{admin_api_host} #{public_api_host}")

dns_servers = search_env_filtered(:node, "roles:dns-server")
if dns_servers.length > 0
  dns_server = dns_servers[0]
  dns_server = node if dns_server.name == node.name
else
  dns_server = node
end
dns_server_public_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(dns_server, "public").address
Chef::Log.info("DNS server found at #{dns_server_public_ip}")

glance_servers = search_env_filtered(:node, "roles:glance-server")
if glance_servers.length > 0
  glance_server = glance_servers[0]
  glance_server = node if glance_server.name == node.name
  glance_server_host = CrowbarHelper.get_host_for_admin_url(glance_server, (glance_server[:glance][:ha][:enabled] rescue false))
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

vncproxies = search_env_filtered(:node, "recipes:nova\\:\\:vncproxy")
if vncproxies.length > 0
  vncproxy = vncproxies[0]
  vncproxy = node if vncproxy.name == node.name
else
  vncproxy = node
end
vncproxy_ha_enabled = vncproxy[:nova][:ha][:enabled]
vncproxy_public_host = CrowbarHelper.get_host_for_public_url(vncproxy, vncproxy[:nova][:novnc][:ssl][:enabled], vncproxy_ha_enabled)
Chef::Log.info("VNCProxy server at #{vncproxy_public_host}")

directory "/etc/nova" do
   mode 0755
   action :create
end

if node[:nova][:use_gitrepo]
  package("libvirt-bin")

  create_user_and_dirs node[:nova][:user] do
    opt_dirs [node[:nova][:instances_path]]
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

keystone_settings = NovaHelper.keystone_settings(node)

cinder_servers = search(:node, "roles:cinder-controller") || []
if cinder_servers.length > 0
  cinder_server = cinder_servers[0]
  cinder_insecure = cinder_server[:cinder][:api][:protocol] == 'https' && cinder_server[:cinder][:ssl][:insecure]
  if cinder_server[:cinder][:volume][:volume_type] == "rbd" and node[:nova][:libvirt_type] == "kvm"
    ceph_env_filter = " AND ceph_config_environment:ceph-config-default"
    ceph_servers = search(:node, "roles:ceph-osd#{ceph_env_filter}") || []
    if ceph_servers.length > 0
      include_recipe('ceph::nova')
    end
    ceph_user = node['ceph']['nova-user']
    ceph_uuid = node['ceph']['nova-uuid']
  end #Ceph section
else
  cinder_insecure = false
  ceph_user = node[:nova][:rbd][:user]
  ceph_uuid = node[:nova][:rbd][:secret_uuid]
end

neutron_servers = search_env_filtered(:node, "roles:neutron-server")
if neutron_servers.length > 0
  neutron_server = neutron_servers[0]
  neutron_server = node if neutron_server.name == node.name
  neutron_protocol = neutron_server[:neutron][:api][:protocol]
  neutron_server_host = CrowbarHelper.get_host_for_admin_url(neutron_server, (neutron_server[:neutron][:ha][:enabled] rescue false))
  neutron_server_port = neutron_server[:neutron][:api][:service_port]
  neutron_insecure = neutron_protocol == 'https' && neutron_server[:neutron][:ssl][:insecure]
  neutron_service_user = neutron_server[:neutron][:service_user]
  neutron_service_password = neutron_server[:neutron][:service_password]
  neutron_networking_plugin = neutron_server[:neutron][:networking_plugin]
  neutron_networking_mode = neutron_server[:neutron][:networking_mode]
  neutron_dhcp_domain = neutron_server[:neutron][:dhcp_domain]
else
  neutron_server_host = nil
  neutron_server_port = nil
  neutron_service_user = nil
  neutron_service_password = nil
  neutron_dhcp_domain = "novalocal"
end
Chef::Log.info("Neutron server at #{neutron_server_host}")

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

# only require certs for nova controller
if api == node and api[:nova][:ssl][:enabled] and node["roles"].include?("nova-multi-controller")
  if api[:nova][:ssl][:generate_certs]
    package "openssl"
    ruby_block "generate_certs for nova" do
      block do
        unless ::File.exists? api[:nova][:ssl][:certfile] and ::File.exists? api[:nova][:ssl][:keyfile]
          require "fileutils"

          Chef::Log.info("Generating SSL certificate for nova...")

          [:certfile, :keyfile].each do |k|
            dir = File.dirname(api[:nova][:ssl][k])
            FileUtils.mkdir_p(dir) unless File.exists?(dir)
          end

          # Generate private key
          %x(openssl genrsa -out #{api[:nova][:ssl][:keyfile]} 4096)
          if $?.exitstatus != 0
            message = "SSL private key generation failed"
            Chef::Log.fatal(message)
            raise message
          end
          FileUtils.chown "root", api[:nova][:group], api[:nova][:ssl][:keyfile]
          FileUtils.chmod 0640, api[:nova][:ssl][:keyfile]

          # Generate certificate signing requests (CSR)
          conf_dir = File.dirname api[:nova][:ssl][:certfile]
          ssl_csr_file = "#{conf_dir}/signing_key.csr"
          ssl_subject = "\"/C=US/ST=Unset/L=Unset/O=Unset/CN=#{api[:fqdn]}\""
          %x(openssl req -new -key #{api[:nova][:ssl][:keyfile]} -out #{ssl_csr_file} -subj #{ssl_subject})
          if $?.exitstatus != 0
            message = "SSL certificate signed requests generation failed"
            Chef::Log.fatal(message)
            raise message
          end

          # Generate self-signed certificate with above CSR
          %x(openssl x509 -req -days 3650 -in #{ssl_csr_file} -signkey #{api[:nova][:ssl][:keyfile]} -out #{api[:nova][:ssl][:certfile]})
          if $?.exitstatus != 0
            message = "SSL self-signed certificate generation failed"
            Chef::Log.fatal(message)
            raise message
          end

          File.delete ssl_csr_file  # Nobody should even try to use this
        end # unless files exist
      end # block
    end # ruby_block
  else # if generate_certs
    unless ::File.exists? api[:nova][:ssl][:certfile]
      message = "Certificate \"#{api[:nova][:ssl][:certfile]}\" is not present."
      Chef::Log.fatal(message)
      raise message
    end
    # we do not check for existence of keyfile, as the private key is allowed
    # to be in the certfile
  end # if generate_certs

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
  # No check if we're using certificate info from nova-api
  unless ::File.exists? api_novnc_ssl_certfile or api[:nova][:novnc][:ssl][:certfile].empty?
    message = "Certificate \"#{api_novnc_ssl_certfile}\" is not present."
    Chef::Log.fatal(message)
    raise message
  end
end

admin_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
metadata_bind_address = admin_address

if node[:nova][:ha][:enabled]
  bind_host = admin_address
  bind_port_api = node[:nova][:ha][:ports][:api]
  bind_port_api_ec2 = node[:nova][:ha][:ports][:api_ec2]
  bind_port_metadata = node[:nova][:ha][:ports][:metadata]
  bind_port_objectstore = node[:nova][:ha][:ports][:objectstore]
  bind_port_novncproxy = node[:nova][:ha][:ports][:novncproxy]
  bind_port_xvpvncproxy = node[:nova][:ha][:ports][:xvpvncproxy]
else
  bind_host = "0.0.0.0"
  bind_port_api = 8774
  bind_port_api_ec2 = 8773
  bind_port_metadata = 8775
  bind_port_objectstore = 3333
  bind_port_novncproxy = 6080
  bind_port_xvpvncproxy = 6081
end

template "/etc/nova/nova.conf" do
  source "nova.conf.erb"
  owner node[:nova][:user]
  group "root"
  mode 0640
  variables(
            :bind_host => bind_host,
            :bind_port_api => bind_port_api,
            :bind_port_api_ec2 => bind_port_api_ec2,
            :bind_port_metadata => bind_port_metadata,
            :bind_port_objectstore => bind_port_objectstore,
            :bind_port_novncproxy => bind_port_novncproxy,
            :bind_port_xvpvncproxy => bind_port_xvpvncproxy,
            :dhcpbridge => "#{node[:nova][:use_gitrepo] ? nova_path:"/usr"}/bin/nova-dhcpbridge",
            :database_connection => database_connection,
            :rabbit_settings => rabbit_settings,
            :libvirt_type => node[:nova][:libvirt_type],
            :ec2_host => admin_api_host,
            :ec2_dmz_host => public_api_host,
            :libvirt_migration => node[:nova]["use_migration"],
            :shared_instances => node[:nova]["use_shared_instance_storage"],
            :dns_server_public_ip => dns_server_public_ip,
            :glance_server_protocol => glance_server_protocol,
            :glance_server_host => glance_server_host,
            :glance_server_port => glance_server_port,
            :glance_server_insecure => glance_server_insecure,
            :metadata_bind_address => metadata_bind_address,
            :vncproxy_public_host => vncproxy_public_host,
            :vncproxy_ssl_enabled => api[:nova][:novnc][:ssl][:enabled],
            :vncproxy_cert_file => api_novnc_ssl_certfile,
            :vncproxy_key_file => api_novnc_ssl_keyfile,
            :neutron_protocol => neutron_protocol,
            :neutron_server_host => neutron_server_host,
            :neutron_server_port => neutron_server_port,
            :neutron_insecure => neutron_insecure,
            :neutron_service_user => neutron_service_user,
            :neutron_service_password => neutron_service_password,
            :neutron_networking_plugin => neutron_networking_plugin,
            :neutron_dhcp_domain => neutron_dhcp_domain,
            :keystone_settings => keystone_settings,
            :cinder_insecure => cinder_insecure,
            :ceph_user => ceph_user,
            :ceph_uuid => ceph_uuid,
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

