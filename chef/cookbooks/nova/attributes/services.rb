case node["platform"]
when "suse"
  default["nova"]["services"] = {
    "compute" => {
      "kvm" => ["libvirtd","openstack-nova-compute"],
      "qemu" => ["libvirtd","openstack-neutron-openvswitch-agent","openstack-neutron-ovs-cleanup","openstack-nova-compute","openvswitch-switch"],
      "vmware" => ["dnsmasq","libvirtd","openstack-neutron-openvswitch-agent","openstack-neutron-ovs-cleanup","openstack-nova-compute","openvswitch-switch"],
      "xen" => ["openstack-neutron-openvswitch-agent","openstack-neutron-ovs-cleanup","openstack-nova-rpc-zmq-receiver","openstack-nova-compute","xen-watchdog","xencommons","xend","xendomains","openvswitch-switch"]
    },
    "controller" => ["openstack-nova-api","openstack-nova-conductor","openstack-nova-cert","openstack-nova-objectstore","openstack-nova-consoleauth","openstack-nova-novncproxy","openstack-nova-scheduler"]
  }
end
