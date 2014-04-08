unless node["roles"].include?("nova-multi-controller")
  node["nova"]["services"]["controller"].each do |name|
    service name do
      action [:stop, :disable]
    end
  end
  node["nova"]["services"].delete("controller")
  node.delete("nova") if node["nova"]["services"].empty?
  node.save
end
