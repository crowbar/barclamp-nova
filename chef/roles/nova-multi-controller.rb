name "nova-multi-controller"

description "Installs requirements to run the Controller node in a Nova cluster"
run_list(
         "recipe[nova::config]",
         "recipe[nova::database]",
         "recipe[nova::api]",
         "recipe[nova::cert]",
         "recipe[nova::network]",
         "recipe[nova::instances]",
         "recipe[nova::scheduler]",
         "recipe[nova::vncproxy]",
         "recipe[nova::project]",
         "recipe[nova::trusted_flavors]",
         "recipe[nova::monitor]"
         )
