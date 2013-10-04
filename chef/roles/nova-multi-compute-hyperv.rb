name "nova-multi-compute-hyperv"
description "Installs requirements to run a Compute node in a Nova cluster"
run_list(
         "recipe[hyperv::windows_features]",
         "recipe[hyperv::setup_networking]",
         "recipe[hyperv::7zip]",
         "recipe[hyperv::python]",
         "recipe[hyperv::python_archive]",
         "recipe[hyperv::openstack_install]",
         "recipe[hyperv::config]",
         "recipe[hyperv::register_services]"
)
default_attributes()
override_attributes()
