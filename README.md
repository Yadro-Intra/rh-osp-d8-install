# rh-osp-d8-install
## Some hints and scripts for installation of RH OpenStack Platform using Director 8

These scripts somehow automate actions described in [the manual](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/).

They aren't intended for use "as is", treat'em as templates (at least read them before execute!).

* `sect-4.7.sh` - see [4.7. Obtaining Images for Overcloud Nodes](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/47-obtaining-images-for-overcloud-nodes)
* `sect-4.8.sh` - see [4.8. Setting a Nameserver on the Undercloud's Neutron Subnet](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/48-setting-a-nameserver-on-the-underclouds-neutron-subnet)
* `sect-4.9.sh` - see [4.9. Backing Up the Undercloud](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/49-backing-up-the-undercloud) (between Chapter 6 and Chapter 7!), but actually it's [Backup and Restore the Director undercloud](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/back-up-and-restore-red-hat-openstack-platform/back-up-and-restore-red-hat-openstack-platform)
* `sect-4.10.sh` - see /4.10. Completing the Undercloud Configuration/ (empty section)
* `sect-5.1.sh` - see [⁠5.1. Registering Nodes for the Overclod](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/chapter-5-configuring-basic-overcloud-requirements)
* `sect-5.2.sh` - see [5.2. Inspecting the Hardware of Nodes](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/52-inspecting-the-hardware-of-nodes)
* `sect-5.3.sh` - see [5.3. Tagging Nodes into Profiles](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/53-tagging-nodes-into-profiles)

* `certgen.py` - see [Appendix A. SSL/TLS Certificate Configuration](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/appendix-a-ssl-tls-certificate-configuration) as referred from [4.6. Configuring the Director](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/46-configuring-the-director) and [6.11. Enabling SSL/TLS on the Overcloud](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/611-enabling-ssl-tls-on-the-overcloud)
* `recvRawEth.c` - sorta `tcpdump`. Tailored to 5.1 to help detect MAC addresses.
* `sect-6.10.sh` - **ACHTUNG!** The last command starts "Overcloud" deployment without declaration of war! It does **not** merely apply timezone changes!

