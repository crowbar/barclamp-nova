# Copyright 2011, Dell 
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

class NovaController < BarclampController
  def nodes
    disk_list = {}
    name = params[:id] || params[:name]
    node = NodeObject.find_node_by_name(name)
    node["crowbar"]["disks"].each do | disk, data |
      disk_list[disk] = data["size"] if data["usage"] == "Storage"
    end
    Rails.logger.info "disk list #{disk_list.inspect}"
    render :json => JSON.generate(disk_list), :layout=>false
  end
end

