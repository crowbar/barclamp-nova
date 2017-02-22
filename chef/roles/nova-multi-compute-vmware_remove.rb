name "nova-multi-compute-vmware_remove"
description "Deactivate Nova vmware Role services"
run_list(
  "recipe[nova::deactivate_compute]"
)
default_attributes()
override_attributes()
