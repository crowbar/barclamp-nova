name "nova-multi-compute-lxc"
description "Installs requirements to run a Compute node in a Nova cluster"
run_list(
         "recipe[nova::lxc]",
         "recipe[nova::compute]",
         "recipe[nova::monitor]"
         )
