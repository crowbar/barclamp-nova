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

sql_engine = node[:nova][:db][:sql_engine]

include_recipe "#{sql_engine}::client"

# find sql server
env_filter = " AND #{sql_engine}_config_environment:#{sql_engine}-config-#{node[:nova][:db][:sql_instance]}"
db_server = search(:node, "roles:#{sql_engine}-server#{env_filter}")
# if we found ourself, then use us.
if db_server[0]['fqdn'] == node['fqdn']
  db_server = [ node ]
end

log "DBServer: #{db_server[0][sql_engine].api_bind_host}"

db_conn = { :host => db_server[0][sql_engine]['api_bind_host'],
            :username => "db_maker",
            :password => db_server[0][sql_engine]['db_maker_password'] }
db_provider=nil
db_user_provider=nil

case sql_engine
  when "mysql"
    db_provider=Chef::Provider::Database::Mysql
    db_user_provider=Chef::Provider::Database::MysqlUser
    privs = [ "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE",
              "DROP", "INDEX", "ALTER" ]
  when "postgresql"
    db_provider=Chef::Provider::Database::Postgresql
    db_user_provider=Chef::Provider::Database::PostgresqlUser
    privs = [ "CREATE", "CONNECT", "TEMP" ]
end

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
  command "nova-manage db sync"
  action :run
end

# save data so it can be found by search
node.save

