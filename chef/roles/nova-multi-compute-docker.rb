name "nova-multi-compute-docker"
description "Installs requirements to run a Compute node in a Nova cluster"
run_list(
         "recipe[nova::docker]",
         "recipe[nova::compute]",
         "recipe[nova::monitor]"
         )
