name "nova-multi-compute-hyperv"
description "Installs requirements to run a Compute node in a Nova cluster"
run_list(
         "recipe[hyperv::do_setup]",
         "recipe[hyperv::do_nova]"
)
default_attributes()
override_attributes()
