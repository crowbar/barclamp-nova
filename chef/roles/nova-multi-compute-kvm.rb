# -*- encoding : utf-8 -*-
name "nova-multi-compute-kvm"
description "Installs requirements to run a Compute node in a Nova cluster"
run_list(
         "recipe[nova::kvm]",
         "recipe[nova::compute]",
         "recipe[nova::monitor]"
         )
