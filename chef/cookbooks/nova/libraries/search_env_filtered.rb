class Chef
  class Recipe
    def search_env_filtered(type, query="*:*", sort='X_CHEF_id_CHEF_X asc', start=0, rows=100, &block)
      # All cookbooks encode the barclamp name as the role name prefix, thus we can
      # simply grab it from the query (e.g. BC 'keystone' for role 'keystone-server'):
      barclamp = /^\w*:(\w*).*$/.match(query)[1]

      # There are two conventions to filter by barclamp proposal:
      #  1) Other barclamp cookbook: node[@cookbook_name][$OTHER_BC_NAME_instance]
      #  2) Same cookbook: node[@cookbook_name][:config][:environment]
      if barclamp == @cookbook_name
        env = node[:nova][:config][:environment]
      else
        env = "#{barclamp}-config-#{node[@cookbook_name]["#{barclamp}_instance"]}"
      end
      filtered_query = "#{query} AND #{barclamp}_config_environment:#{env}"
      if block
        return search(type, filtered_query, sort, start, rows, &block)
      else
        return search(type, filtered_query, sort, start, rows)[0]
      end
    end
  end
end
