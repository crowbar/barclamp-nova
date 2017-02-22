name "nova-multi-compute-kvm_remove"
description "Deactivate Nova kvm Role services"
run_list(
  "recipe[nova::deactivate_compute]"
)
default_attributes()
override_attributes()
