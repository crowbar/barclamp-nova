# -*- encoding : utf-8 -*-
module NovaHelper
  class << self
    def keystone_settings(node)
      @keystone_settings ||= nil

      if @keystone_settings.nil?
        # we can't use get_instance from here :/
        #keystone_node = Chef::Recipe.get_instance('roles:keystone-server')
        nodes = []
        Chef::Search::Query.new.search(:node, "roles:keystone-server AND keystone_config_environment:keystone-config-#{node[:nova][:keystone_instance]}") { |o| nodes << o }
        if nodes.empty?
          keystone_node = node
        else
          keystone_node = nodes[0]
          keystone_node = node if keystone_node.name == node.name
        end

        @keystone_settings = KeystoneHelper.keystone_settings(keystone_node)
        @keystone_settings['service_user'] = node[:nova][:service_user]
        @keystone_settings['service_password'] = node[:nova][:service_password]
        Chef::Log.info("Keystone server found at #{@keystone_settings['internal_url_host']}")
      end

      @keystone_settings
    end
  end
end
