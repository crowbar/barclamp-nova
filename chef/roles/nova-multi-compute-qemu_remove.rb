name "nova-multi-compute-qemu_remove"
description "Deactivate Nova qemu Role services"
run_list(
  "recipe[nova::deactivate_compute]"
)
default_attributes()
override_attributes()
