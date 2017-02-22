name "nova-multi-compute-xen_remove"
description "Deactivate Nova xen Role services"
run_list(
  "recipe[nova::deactivate_compute]"
)
default_attributes()
override_attributes()
