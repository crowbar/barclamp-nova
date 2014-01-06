#
# Cookbook Name:: nova
# Recipe:: database
#
# Copyright 2010-2011, Opscode, Inc.
# Copyright 2011, Dell, Inc.
# Copyright 2012, SUSE Linux Products GmbH.
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

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)

include_recipe "database::client"

# find sql server
sqls = search_env_filtered(:node, "roles:database-server")
# if we found ourself, then use us.
if sqls.length > 0
    sql = sqls[0]
    sql = node if sql.name == node.name
else
    sql = node
end

log "DBServer: #{sql["database"].api_bind_host}"

db_conn = { :host => sql["database"]['api_bind_host'],
            :username => "db_maker",
            :password => sql["database"]['db_maker_password'] }

db_provider = Chef::Recipe::Database::Util.get_database_provider(sql)
db_user_provider = Chef::Recipe::Database::Util.get_user_provider(sql)
privs = Chef::Recipe::Database::Util.get_default_priviledges(sql)

# Creates empty nova database
database "create #{node[:nova][:db][:database]} database" do
  connection db_conn
  database_name node[:nova][:db][:database]
  provider db_provider
  action :create
end

database_user "create nova database user" do
  connection db_conn
  username node[:nova][:db][:user]
  password node[:nova][:db][:password]
  provider db_user_provider
  action :create
end

database_user "grant privileges to the nova database user" do
  connection db_conn
  database_name node[:nova][:db][:database]
  username node[:nova][:db][:user]
  password node[:nova][:db][:password]
  host '%'
  privileges privs
  provider db_user_provider
  action :grant
end

execute "nova-manage db sync" do
  user node[:nova][:user]
  group node[:nova][:group]
  command "nova-manage db sync"
  action :run
end

# save data so it can be found by search
node.save

