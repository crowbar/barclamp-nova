name "nova-multi-controller_remove"
description "Deactivate Nova Controller Role services"
run_list(
  "recipe[nova::deactivate_controller]"
)
default_attributes()
override_attributes()
