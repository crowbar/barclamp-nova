Base Commit is: 0d6787b190a255c97465c53e734196b2bbe82631

533,535c533
<                 LOG.info("Attaching device with virsh because attachDevice does not work")
<                 device_path = connection_info['data']['device_path']
<                 utils.execute('virsh', "attach-disk", instance_name, device_path, mount_device, run_as_root=True)
---
>                 virt_dom.attachDevice(xml)

