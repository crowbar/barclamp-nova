include_recipe "ceph::keyring"

case node[:platform]
when "suse"
  package "python-ceph"
  package "qemu-block-rbd" do
    action :install
    only_if { node[:platform_version].to_f >= 12.0 }
  end
end

# TODO cluster name
cluster = 'ceph'

cinder_controller = search(:node, "roles:cinder-controller")
if cinder_controller.length > 0
  cinder_pools = []
  cinder_controller[0][:cinder][:volumes].each do |volume|
    next unless (volume['backend_driver'] == "rbd") && volume['rbd']['use_crowbar']
    cinder_pools << volume[:rbd][:pool]
  end

  nova_user = 'nova'

  nova_uuid = is_crowbar? ? "" : node["ceph"]["config"]["fsid"]
  if nova_uuid.nil? || nova_uuid.empty?
    mons = get_mon_nodes("ceph_admin-secret:*")
    if mons.empty? then
      Chef::Log.fatal("No ceph-mon found")
      raise "No ceph-mon found"
    end

    nova_uuid = mons[0]["ceph"]["config"]["fsid"]
  end

  allow_pools = cinder_pools.map{|p| "allow rwx pool=#{p}"}.join(", ")
  ceph_caps = { 'mon' => 'allow r', 'osd' => "allow class-read object_prefix rbd_children, #{allow_pools}" }

  ceph_client nova_user do
    caps ceph_caps
    keyname "client.#{nova_user}"
    filename "/etc/ceph/ceph.client.#{nova_user}.keyring"
    owner "root"
    group node[:nova][:group]
    mode 0640
  end

  secret_file_path = "/etc/ceph/ceph-secret.xml"

  file secret_file_path do
    owner "root"
    group "root"
    mode "0640"
    content "<secret ephemeral='no' private='no'> <uuid>#{nova_uuid}</uuid><usage type='ceph'> <name>client.#{nova_user} secret</name> </usage> </secret>"
  end #file secret_file_path

  ruby_block "save nova key as libvirt secret" do
    block do
      if system("virsh hostname &> /dev/null")
        # First remove conflicting secrets due to same usage name
        secret_list = %x[ virsh secret-list 2> /dev/null ]

        secret_lines = secret_list.split("\n")
        if secret_lines.length < 2 || !secret_lines[0].start_with?("UUID") || !secret_lines[1].start_with?("----")
          raise "cannot fetch list of libvirt secret"
        end
        secret_lines.shift(2)

        secret_lines.each do |secret_line|
          secret_uuid = secret_line.split(" ")[0]
          secret_xml = %x[ virsh secret-dumpxml #{secret_uuid} ]
          # some secrets might not be ceph-related, skip these
          next if secret_xml.index("<usage type='ceph'>").nil?

          # lazy xml parsing
          re_match = %r[<usage type='ceph'>.*<name>(.*)</name>]m.match(secret_xml)
          next if re_match.nil?
          secret_usage = re_match[1]

          undefine = false

          if secret_uuid == nova_uuid
            undefine = true if secret_usage != "client.#{nova_user} secret"
          else
            undefine = true if secret_usage == "client.#{nova_user} secret"
          end

          if undefine
            %x[ virsh secret-undefine #{secret_uuid} ]
          end
        end

        # Now add our secret and its value
        client_key = %x[ ceph auth get-key client.'#{nova_user}' ]
        raise 'getting nova client key failed' unless $?.exitstatus == 0

        secret = %x[ virsh secret-get-value #{nova_uuid} 2> /dev/null ].chomp.strip
        if secret != client_key
          %x[ virsh secret-define --file '#{secret_file_path}' ]
          raise 'generating secret file failed' unless $?.exitstatus == 0

          %x[ virsh secret-set-value --secret '#{nova_uuid}' --base64 '#{client_key}' ]
          raise 'importing secret file failed' unless $?.exitstatus == 0
        end
      end
    end
  end

  if node['ceph']['nova-user'] != nova_user || node['ceph']['nova-uuid'] != nova_uuid
    node['ceph']['nova-user'] = nova_user
    node['ceph']['nova-uuid'] = nova_uuid
    node.save
  end
end
