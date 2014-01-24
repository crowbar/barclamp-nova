# Copyright 2014, SUSE Linux Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

define :virsh_secret, :username => "", :passphrase => "" do

  username = params[:username]
  passphrase = params[:passphrase]

  bash "virsh_secret_set_value" do
    code <<-EOF
      #!/bin/bash

      t=$(mktemp)
      echo "<secret ephemeral='no' private='no'> \
           <auth type='ceph' username='#{username}'/><usage type='ceph'> \
           <name>client.#{username}</name></usage></secret>" > $t
      uuid=$(virsh secret-define $t 2>&1 | egrep -o " [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12} ")
      rm -f $t
      virsh secret-set-value "$uuid" --base64 "#{passphrase}"
    EOF
    timeout 5
  end
end
