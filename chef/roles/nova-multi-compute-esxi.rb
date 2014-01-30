name "nova-multi-compute-esxi"
description "Installs requirements to run a Compute node in a Nova cluster"
run_list(
         "recipe[nova::esxi]",
         "recipe[nova::compute]",
         "recipe[nova::monitor]"
         )
