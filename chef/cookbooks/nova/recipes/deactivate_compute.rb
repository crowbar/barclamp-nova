def deactivate_service(hypervisor)
  node["nova"]["services"]["compute"][hypervisor].each do |name|
    service name do
      action [:stop, :disable]
    end
  end
  node["nova"]["services"].delete("compute")
  node.delete("nova") if node["nova"]["services"].empty?
  node.save
end

# hyperv needs to be added
unless node["roles"].include?("nova-multi-compute-#{node[:nova][:libvirt_type]}")
  case node["nova"]["libvirt_type"]
  when "kvm"
    deactivate_service("kvm")
  when "xen"
    deactivate_service("xen")
  when "vmware"
    deactivate_service("vmware")
  when "qemu"
    deactivate_service("qemu")
  end
end
