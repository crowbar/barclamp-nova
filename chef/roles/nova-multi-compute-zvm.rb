name "nova-multi-compute-zvm"
description "Installs requirements to run a Compute node in a Nova cluster"
run_list(
         "recipe[nova::zvm]",
         "recipe[nova::compute]",
         "recipe[nova::monitor]"
         )
