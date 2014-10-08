if node[:nova][:trusted_flavors]
 flavors={11=>
   {"name"=>"m1.trusted.large",
    "vcpu"=>4,
    "disk"=>80,
    "mem"=>4096},
  12=>
   {"name"=>"m1.trusted.xlarge",
    "vcpu"=>8,
    "disk"=>80,
    "mem"=>8192},
  8=>
   {"name"=>"m1.trusted.tiny",
    "vcpu"=>1,
    "disk"=>0,
    "mem"=>512},
  9=>
   {"name"=>"m1.trusted.small",
    "vcpu"=>1,
    "disk"=>20,
    "mem"=>2048},
  10=>
   {"name"=>"m1.trusted.medium",
    "vcpu"=>2,
    "disk"=>40,
    "mem"=>4096}
 }


  nova = node
  keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

  nova_insecure = node[:nova][:ssl][:insecure]
  ssl_insecure = keystone_settings['insecure'] || nova_insecure

  novacmd = "nova --os-username #{keystone_settings['service_user']} --os-password #{keystone_settings['service_password']} --os-tenant-name #{keystone_settings['service_tenant']} --os-auth-url #{keystone_settings['internal_auth_url']} --endpoint-type internalURL --os-region-name '#{keystone_settings['endpoint_region']}'"
  if ssl_insecure
    novacmd = "#{novacmd} --insecure"
  end

  flavors.keys.each do |id|
    execute "register_#{flavors[id]["name"]}_flavor" do
      command <<-EOF
        #{novacmd} flavor-create #{flavors[id]["name"]} #{id} #{flavors[id]["mem"]} #{flavors[id]["disk"]} #{flavors[id]["vcpu"]}
        #{novacmd} flavor-key #{flavors[id]["name"]} set trust:trusted_host=trusted
      EOF
      not_if "#{novacmd} flavor-show #{id}"
    end
  end

end
