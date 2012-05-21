name "nova-multi-volume"
description "Installs requirements to run a volume node in a Nova cluster"
run_list(
         "recipe[nova::volume]",
         "recipe[nova::monitor]"
         )
