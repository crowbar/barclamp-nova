# -*- encoding : utf-8 -*-
name "nova-multi-compute-vmware"
description "Installs requirements to run a Compute node in a Nova cluster"
run_list(
         "recipe[nova::vmware]",
         "recipe[nova::compute]",
         "recipe[nova::monitor]"
         )
