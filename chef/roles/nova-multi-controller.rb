name "nova-multi-controller"

description "Installs requirements to run the Controller node in a Nova cluster"
run_list(
         "recipe[nova::mysql]",
         "recipe[rabbitmq]",
         "recipe[nova::rabbit]",
         "recipe[nova::api]",
         "recipe[nova::network]",
         "recipe[nova::scheduler]",
         "recipe[nova::vncproxy]",
         "recipe[nova::project]",
         "recipe[nova::monitor]"
         )
