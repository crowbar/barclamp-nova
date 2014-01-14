name "nova-multi-compute-xen"
description "Installs requirements to run a Compute node in a Nova cluster"
run_list(
         "recipe[nova::xen]",
         "recipe[nova::compute]",
         "recipe[nova::monitor]"
         )
