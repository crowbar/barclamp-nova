#
# Cookbook Name:: nova
# Recipe:: docker
#
# Copyright 2010, Opscode, Inc.
# Copyright 2011, Dell, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

node.set[:nova][:libvirt_type] = "docker"


# if tempest is deployed, load packaged docker image at docker compute node
tempest_node = search(:node, "roles:tempest").first
unless tempest_node.nil?
  docker_image = tempest_node[:tempest][:tempest_test_docker_image] || ""

  bash "load docker image" do
    code <<-EOH
      TEMP=$(mktemp -d)
      IMG_FILE=$(basename #{docker_image})

      wget --no-verbose #{docker_image} --directory-prefix=$TEMP 2>&1 || exit $?
      docker load --input=$TEMP/$IMG_FILE
      mkdir -p /var/lib/crowbar
      touch /var/lib/crowbar/docker_for_tempest_loaded
      rm -rf $TEMP
EOH
    not_if { docker_image.empty? || ::File.exists?("/var/lib/crowbar/docker_for_tempest_loaded") }
  end
end
