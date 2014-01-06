name "nova-multi-compute-qemu"
description "Installs requirements to run a Compute node in a Nova cluster"
run_list(
         "recipe[nova::qemu]",
         "recipe[nova::compute]",
         "recipe[nova::monitor]"
         )
