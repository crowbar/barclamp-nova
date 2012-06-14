# vim: tabstop=4 shiftwidth=4 softtabstop=4

# Copyright (c) 2011 OpenStack, LLC.
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.


from nova.rootwrap import filters

filterlist = [
    # nova/virt/disk/mount.py: 'kpartx', '-a', device
    # nova/virt/disk/mount.py: 'kpartx', '-d', device
    filters.CommandFilter("/sbin/kpartx", "root"),

    # nova/virt/disk/mount.py: 'tune2fs', '-c', 0, '-i', 0, mapped_device
    # nova/virt/xenapi/vm_utils.py: "tune2fs", "-O ^has_journal", part_path
    # nova/virt/xenapi/vm_utils.py: "tune2fs", "-j", partition_path
    filters.CommandFilter("/sbin/tune2fs", "root"),

    # nova/virt/disk/mount.py: 'mount', mapped_device, mount_dir
    # nova/virt/xenapi/vm_utils.py: 'mount', '-t', 'ext2,ext3,ext4,reiserfs'..
    filters.CommandFilter("/bin/mount", "root"),

    # nova/virt/disk/mount.py: 'umount', mapped_device
    # nova/virt/xenapi/vm_utils.py: 'umount', dev_path
    filters.CommandFilter("/bin/umount", "root"),

    # nova/virt/disk/nbd.py: 'qemu-nbd', '-c', device, image
    # nova/virt/disk/nbd.py: 'qemu-nbd', '-d', device
    filters.CommandFilter("/usr/bin/qemu-nbd", "root"),

    # nova/virt/disk/loop.py: 'losetup', '--find', '--show', image
    # nova/virt/disk/loop.py: 'losetup', '--detach', device
    filters.CommandFilter("/sbin/losetup", "root"),

    # nova/virt/disk/guestfs.py: 'guestmount', '--rw', '-a', image, '-i'
    # nova/virt/disk/guestfs.py: 'guestmount', '--rw', '-a', image, '-m' dev
    filters.CommandFilter("/usr/bin/guestmount", "root"),

    # nova/virt/disk/guestfs.py: 'fusermount', 'u', mount_dir
    filters.CommandFilter("/bin/fusermount", "root"),
    filters.CommandFilter("/usr/bin/fusermount", "root"),

    # nova/virt/disk/api.py: 'tee', metadata_path
    # nova/virt/disk/api.py: 'tee', '-a', keyfile
    # nova/virt/disk/api.py: 'tee', netfile
    filters.CommandFilter("/usr/bin/tee", "root"),

    # nova/virt/disk/api.py: 'mkdir', '-p', sshdir
    # nova/virt/disk/api.py: 'mkdir', '-p', netdir
    filters.CommandFilter("/bin/mkdir", "root"),

    # nova/virt/disk/api.py: 'chown', 'root', sshdir
    # nova/virt/disk/api.py: 'chown', 'root:root', netdir
    # nova/virt/libvirt/connection.py: 'chown', os.getuid(), console_log
    # nova/virt/libvirt/connection.py: 'chown', os.getuid(), console_log
    # nova/virt/libvirt/connection.py: 'chown', 'root', basepath('disk')
    # nova/utils.py: 'chown', owner_uid, path
    filters.CommandFilter("/bin/chown", "root"),

    # nova/virt/disk/api.py: 'chmod', '700', sshdir
    # nova/virt/disk/api.py: 'chmod', 755, netdir
    filters.CommandFilter("/bin/chmod", "root"),

    # nova/virt/disk/api.py: 'cp', os.path.join(fs...
    filters.CommandFilter("/bin/cp", "root"),

    # nova/virt/libvirt/vif.py: 'ip', 'tuntap', 'add', dev, 'mode', 'tap'
    # nova/virt/libvirt/vif.py: 'ip', 'link', 'set', dev, 'up'
    # nova/virt/libvirt/vif.py: 'ip', 'link', 'delete', dev
    # nova/network/linux_net.py: 'ip', 'addr', 'add', str(floating_ip)+'/32'i..
    # nova/network/linux_net.py: 'ip', 'addr', 'del', str(floating_ip)+'/32'..
    # nova/network/linux_net.py: 'ip', 'addr', 'add', '169.254.169.254/32',..
    # nova/network/linux_net.py: 'ip', 'addr', 'show', 'dev', dev, 'scope',..
    # nova/network/linux_net.py: 'ip', 'addr', 'del/add', ip_params, dev)
    # nova/network/linux_net.py: 'ip', 'addr', 'del', params, fields[-1]
    # nova/network/linux_net.py: 'ip', 'addr', 'add', params, bridge
    # nova/network/linux_net.py: 'ip', '-f', 'inet6', 'addr', 'change', ..
    # nova/network/linux_net.py: 'ip', 'link', 'set', 'dev', dev, 'promisc',..
    # nova/network/linux_net.py: 'ip', 'link', 'add', 'link', bridge_if ...
    # nova/network/linux_net.py: 'ip', 'link', 'set', interface, "address",..
    # nova/network/linux_net.py: 'ip', 'link', 'set', interface, 'up'
    # nova/network/linux_net.py: 'ip', 'link', 'set', bridge, 'up'
    # nova/network/linux_net.py: 'ip', 'addr', 'show', 'dev', interface, ..
    # nova/network/linux_net.py: 'ip', 'link', 'set', dev, "address", ..
    # nova/network/linux_net.py: 'ip', 'link', 'set', dev, 'up'
    filters.CommandFilter("/sbin/ip", "root"),

    # nova/virt/libvirt/vif.py: 'tunctl', '-b', '-t', dev
    # nova/network/linux_net.py: 'tunctl', '-b', '-t', dev
    filters.CommandFilter("/usr/sbin/tunctl", "root"),

    # nova/virt/libvirt/vif.py: 'ovs-vsctl', ...
    # nova/virt/libvirt/vif.py: 'ovs-vsctl', 'del-port', ...
    # nova/network/linux_net.py: 'ovs-vsctl', ....
    filters.CommandFilter("/usr/bin/ovs-vsctl", "root"),

    # nova/network/linux_net.py: 'ovs-ofctl', ....
    filters.CommandFilter("/usr/bin/ovs-ofctl", "root"),

    # nova/virt/libvirt/connection.py: 'dd', "if=%s" % virsh_output, ...
    filters.CommandFilter("/bin/dd", "root"),
    filters.CommandFilter("/usr/bin/virsh", "root"),

    # nova/virt/xenapi/volume_utils.py: 'iscsiadm', '-m', ...
    filters.CommandFilter("/sbin/iscsiadm", "root"),

    # nova/virt/xenapi/vm_utils.py: "parted", "--script", ...
    # nova/virt/xenapi/vm_utils.py: 'parted', '--script', dev_path, ..*.
    filters.CommandFilter("/sbin/parted", "root"),

    # nova/virt/xenapi/vm_utils.py: fdisk %(dev_path)s
    filters.CommandFilter("/sbin/fdisk", "root"),

    # nova/virt/xenapi/vm_utils.py: "e2fsck", "-f", "-p", partition_path
    filters.CommandFilter("/sbin/e2fsck", "root"),

    # nova/virt/xenapi/vm_utils.py: "resize2fs", partition_path
    filters.CommandFilter("/sbin/resize2fs", "root"),

    # nova/network/linux_net.py: 'ip[6]tables-save' % (cmd,), '-t', ...
    filters.CommandFilter("/sbin/iptables-save", "root"),
    filters.CommandFilter("/sbin/ip6tables-save", "root"),

    # nova/network/linux_net.py: 'ip[6]tables-restore' % (cmd,)
    filters.CommandFilter("/sbin/iptables-restore", "root"),
    filters.CommandFilter("/sbin/ip6tables-restore", "root"),

    # nova/network/linux_net.py: 'arping', '-U', floating_ip, '-A', '-I', ...
    # nova/network/linux_net.py: 'arping', '-U', network_ref['dhcp_server'],..
    filters.CommandFilter("/usr/bin/arping", "root"),

    # nova/network/linux_net.py: 'route', '-n'
    # nova/network/linux_net.py: 'route', 'del', 'default', 'gw'
    # nova/network/linux_net.py: 'route', 'add', 'default', 'gw'
    # nova/network/linux_net.py: 'route', '-n'
    # nova/network/linux_net.py: 'route', 'del', 'default', 'gw', old_gw, ..
    # nova/network/linux_net.py: 'route', 'add', 'default', 'gw', old_gateway
    filters.CommandFilter("/sbin/route", "root"),

    # nova/network/linux_net.py: 'dhcp_release', dev, address, mac_address
    filters.CommandFilter("/usr/bin/dhcp_release", "root"),

    # nova/network/linux_net.py: 'kill', '-9', pid
    # nova/network/linux_net.py: 'kill', '-HUP', pid
    filters.KillFilter("/bin/kill", "root",
                       ['-9', '-HUP'], ['/usr/sbin/dnsmasq']),

    # nova/network/linux_net.py: 'kill', pid
    filters.KillFilter("/bin/kill", "root", [''], ['/usr/sbin/radvd']),

    # nova/network/linux_net.py: dnsmasq call
    filters.DnsmasqFilter("/usr/sbin/dnsmasq", "root"),

    # nova/network/linux_net.py: 'radvd', '-C', '%s' % _ra_file(dev, 'conf'),..
    filters.CommandFilter("/usr/sbin/radvd", "root"),

    # nova/network/linux_net.py: 'brctl', 'addbr', bridge
    # nova/network/linux_net.py: 'brctl', 'setfd', bridge, 0
    # nova/network/linux_net.py: 'brctl', 'stp', bridge, 'off'
    # nova/network/linux_net.py: 'brctl', 'addif', bridge, interface
    filters.CommandFilter("/sbin/brctl", "root"),
    filters.CommandFilter("/usr/sbin/brctl", "root"),

    # nova/virt/libvirt/utils.py: 'mkswap'
    # nova/virt/xenapi/vm_utils.py: 'mkswap'
    filters.CommandFilter("/sbin/mkswap", "root"),

    # nova/virt/xenapi/vm_utils.py: 'mkfs'
    filters.CommandFilter("/sbin/mkfs", "root"),

    # nova/virt/libvirt/utils.py: 'qemu-img'
    filters.CommandFilter("/usr/bin/qemu-img", "root"),

    # nova/virt/disk/api.py: 'touch', target
    filters.CommandFilter("/usr/bin/touch", "root"),

    # nova/virt/libvirt/connection.py:
    filters.ReadFileFilter("/etc/iscsi/initiatorname.iscsi"),

    ]
