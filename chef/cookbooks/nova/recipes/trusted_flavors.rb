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


  nova=node
  env_filter = " AND keystone_config_environment:keystone-config-#{nova[:nova][:keystone_instance]}"
  keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
  if keystones.length > 0
    keystone = keystones[0]
    keystone = node if keystone.name == node.name
  else
    keystone = node
  end

  keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "public").address if keystone_address.nil?
  keystone_service_port = keystone["keystone"]["api"]["service_port"]
  keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
  keystone_service_user = nova["nova"]["service_user"]
  keystone_service_password = nova["nova"]["service_password"]

  flavors.keys.each do |id|
    execute "register_#{flavors[id]["name"]}_flavor" do
      command <<-EOF
        nova --os_username #{keystone_service_user} --os_password #{keystone_service_password} --os_tenant_name #{keystone_service_tenant} --os_auth_url http://#{keystone_address}:#{keystone_service_port}/v2.0 flavor-create #{flavors[id]["name"]} #{id} #{flavors[id]["mem"]} #{flavors[id]["disk"]} #{flavors[id]["vcpu"]}
        nova --os_username #{keystone_service_user} --os_password #{keystone_service_password} --os_tenant_name #{keystone_service_tenant} --os_auth_url http://#{keystone_address}:#{keystone_service_port}/v2.0 flavor-key #{flavors[id]["name"]} set trust:trusted_host=trusted
      EOF
      not_if "nova --os_username #{keystone_service_user} --os_password #{keystone_service_password} --os_tenant_name #{keystone_service_tenant} --os_auth_url http://#{keystone_address}:#{keystone_service_port}/v2.0 flavor-show #{id}"
    end
  end

