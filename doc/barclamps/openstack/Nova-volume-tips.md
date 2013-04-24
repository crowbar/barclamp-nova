> NOTE: move this to Nova Barclamp dir?

# Overview
For Essex, the OpenStack dashboard requires a nova-volume service to function and display properly.  Crowbar’s Nova Barclamp has been updated to have a new role, nova-volume.  The role allows a single node and defaults to the nova-multi-controller.  The goal of this feature in this release is to meet enough to allow progress forward.  It is not optimized for performance.  The volume group is created when the nova proposal is applied.  Changing nova-volume parameters after initial application may not work correctly. There is not code to clean up or remove a volume.

## Crowbar UI

The nova barclamp has the following options for controlling the nova-volume used for the deployment.  

|Attribute|Default|Range|Description|
|---------|---|-------|----------|
| Name of Volume | nova-volumes | String | The name of the volume-group created on the nova-volume node. |
| Type of Volume | raw | raw, local | This field indicates the type of volume to create. If raw is specified, the system attempts to use the remaining unused disks to create a volume group.  If the system doesn’t have additional free drives, the system will switch to local.  Local uses a local file in the existing filesystem based upon other parameters. |
| Volume File Name | /var/lib/nova/volume.raw | Path | When local type is chosen or fallen back to, this field is the name of the file in the file system to use. |
| Maximum File Size | 2000000000000 | Any integer | When local type is chosen or fallen back to, this field defines the maximum size of that file.  If the file is too big for the file system, the size of the file will be capped to 90% of the free space in that filesystem (at the time of creation). |
| Disk Selection Method | all | first, all, selected | When raw type is chosen, this field indicates how to select the disks to use for volume construction.  All means use all available.  First means use the first one detected.  Selected means use the ones selected in the list below this option. |
| Toggle boxes for each disk | None selected | Toggles | These toggles indicate the size and available disks on the node currently in the nova-volume role.  This list is dynamically updated as nodes are move to and from the nova-role in the deployment section.  Selected disks are used exclusively if the raw type is selected. |

Once the nova_dashboard and nova proposals are applied, the OpenStack Dashboard can be used to create, attached, detach, and destroy volumes.  The “Instances & Volumes” tab of the navigation column allow for manipulation for volumes.  These options should function and work.   Volumes can be snapshotted and should be visible in the “Images & Snapshots” tab.    Attached volumes can be validated by logging into the vm and running “fdisk –l”.

## Debugging

The system uses volume groups in linux.  These will be on a local file or raw disks.  On the node running the volume service, the normal linux commands can be used.

|Command|Data returned|
|----|-----|
| losetup -a | Returns the loop devices.  This can be used to find the loop device mounted on the local file |
| vgs | Returns the volume groups on the system.  This can be used to see about the nova volume group |
| vgdisplay <nova volume group> | Detailed information about the volumes.  The name is optional. |
| lvs | Returns the logical volumes on the system.  This can be used to see volumes created inside the volume group |
| lvdisplay <volume name> | Detailed information about the volume.  This name is optional and will show all of them if omitted |
| pvs | Returns a list of physical volumes that can have volume groups.  This shows the physical drives under the volume group.  It will show the loop device from losetup |

When debugging Nova volume, the following logs can be helpful.

|Log|Machine|Data|
|----|----|----|
| /var/log/nova/nova-volume.log | Nova Volume Service (controller usually) | Contains log info around the volume service itself. |
| /var/log/nova/nova-api.log | Nova API Service (controller usually) | Contains log about api requests.  Can see if attach and other calls are being received |
| /var/log/nova/nova-scheduler.log | Nova Scheduler Service (controller usually) | Contains log about scheduler requests for volume operations |
| /var/log/nova/nova-compute.log | Nova Compute Service (compute node) | Contains logs about mounting/attaching/detaching volumes |
| /var/log/libvirt/* | Nova Compute Service (compute node) | Contains hypervisor logs that can reflect volume and instance operations |
| /var/log/messages or /var/log/syslog | System log | Sometimes helpful to see if system level issues are occurring. |

## Questions

Questions off the top of my head on this.

* Where should the Volume service run
  *  These are on the nova-multi-controller by default.  The system has a role for volume.  The volume is a singular entity and can be on anything except as swift storage node.
* Is it possible to add this to an external system?
  * Currently, the code assumes that the node will be on the system and the volume group will be built by crowbar.
* When using local what mount point should it use?  
  * It defaults to /var/lib/nova/nova-volume.raw (see above).
  * The size is capped to 90% of free space for that filesystem.
  * The disk is not reserved or used until data is stored against it.
* How does RAW mode work?
  * Raw mode works similar to Swift physical disks.  All disks that are not declared the OS disk are put in a pool.
  * The disks in the pool are used based upon the selection mode.  All uses all.  First uses the first in the list.  Selected will use the selected disks from the UI.
* Guidance on RAW vs. Local
  * Local can be used for redundancy if the underlying filesystem is RAID10.  This is the Dell RA style today.
  * RAW is better for dealing with larger disk systems and performance at the loss of redundancy currently.
* VMs that attach to the volume service?  Can you explain how they should be used?
  * Volumes are attached to instances in OpenStack.
  * The primary usage is persistent storage across the instances life cycle.
* Will this allow LiveMigration?
  * While not tested or configured, volumes can be used to boot instances from.
  * To do this, a volume would have to be created and populated.  Population would have be done by attaching the image to a running instance, load data, and then detach the volume. This volume could be snapshotted or booted directly from another instance.
  * LiveMigration or Normal Migration could occur over that volume.  WE HAVE NOT TESTED OR TRIED THIS.
* What steps does the system run through to set this up
  * The chef recipes in nova handle the processing of the parameters to setup
  * A loop device is created, if needed.
  * The devices (loop or physical) are added to a volume group.
  * The volume group is created
  * At this point, the volume service takes over and handles logical volume creation and iscsi target setup.
* What happens when you run out of disk?
  * The volume service reports the error to the user through the APIs
* How long does it take to set up a 2T Local file?
  * Almost instantly.  The system uses truncate to create the file.  It is really fast.
* Impact to VMs if the server offering up the volumes is unavailable
  * Instances with attached volumes will function "normally" for a system with a missing disk.  This means that if the user has to manually setup the use of the disk in the instance or has written the instance startup scripts to handle the missing disk, then all is fine.  The data will be missing, but the instance should start.
  * Instances with attached volumes as boot drives will not function.

## Issues
There are some current issues with nova volume that will need to be published.  The main known issue is: https://bugs.launchpad.net/ubuntu/+source/libvirt/+bug/996840.  This bug has been hacked in the code base to work around it. 
