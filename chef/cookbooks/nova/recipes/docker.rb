#
# Cookbook Name:: nova
# Recipe:: docker
#
# Copyright 2013, Dell, Inc.
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

# Author: Judd Maltin


if node.platform == "ubuntu"

  # basic package installation
  package "lxc-docker" do
    action :install
  end

  service "docker" do
    action :start
  end

  node.set[:nova][:compute_driver] = "docker.DockerDriver"


  # setup registry
  # http://get.docker.io/images/openstack/docker-registry.tar.gz
  #
  # setup images, add them to glance
  # TODO: jmaltin
end

