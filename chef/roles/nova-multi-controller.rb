name "nova-multi-controller"

description "Installs requirements to run the Controller node in a Nova cluster"
run_list(
         "recipe[nova::config]",
         "recipe[nova::database]",
         "recipe[nova::api]",
         "recipe[nova::cert]",
         "recipe[nova::instances]",
         "recipe[nova::scheduler]",
         "recipe[nova::memcached]",
         "recipe[nova::vncproxy]",
         "recipe[nova::controller_ha]",
         "recipe[nova::availability_zones]",
         "recipe[nova::trusted_flavors]",
         "recipe[nova::monitor]"
         )
