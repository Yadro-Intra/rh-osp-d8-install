# rh-osp-d8-install
## Some hints and scripts for installation of RH OpenStack Platform using Director 8

These scripts somehow automate actions described in [the manual](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/).

They aren't intended for use "as is", treat'em as templates (at least read them before execute!).

* `sect-4.6.sh` - Configuring the Director. Here you may have troubles with OpenSSL.
* `sect-5.1.sh` - see [⁠5.1. Registering Nodes for the Overclod](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/chapter-5-configuring-basic-overcloud-requirements)
* `sect-6.10.sh` - **ACHTUNG!** The last command starts "Overcloud" deployment without declaration of war! It does **not** merely apply timezone changes!

* `overcloud-deploy.sh` -- script to run for final overcloud deployment.

* `certgen.py` - see [Appendix A. SSL/TLS Certificate Configuration](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/appendix-a-ssl-tls-certificate-configuration) as referred from [4.6. Configuring the Director](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/46-configuring-the-director) and [6.11. Enabling SSL/TLS on the Overcloud](https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/611-enabling-ssl-tls-on-the-overcloud)
* `recvRawEth.c` - sorta `tcpdump`. Tailored to 5.1 to help detect MAC addresses.

