#!/bin/bash
echo 'Chapter 3. Planning your Overcloud'>&2
echo '3.2. Planning Networks'>&2
echo ''>&2

choice=choice.my

declare -A access=(
	[IPMI]="All"
	[Provisioning]="All"
	[Internal]="Controller, Compute, Cinder, Swift"
	[Tenant]="Controller, Compute"
	[Storage]="All"
	[Storage_Mgmt]="Controller, Ceph, Cinder, Swift"
	[External]="Controller"
	[FloatingIP]="Controller"
	[Management]="All"
)

declare -A nets=(
	[IPMI]="Network used for power management of nodes. This network is predefined before the installation of the Undercloud."
	[Provisioning]="The director uses this network traffic type to deploy new nodes over PXE boot and orchestrate the installation of OpenStack Platform on the Overcloud bare metal servers.  This network is predefined before the installation of the Undercloud."
	[Internal]="The Internal API network is used for communication between the OpenStack services using API communication, RPC messages, and database communication."
	[Tenant]="Neutron provides each tenant with their own networks using either VLAN segregation (where each tenant network is a network VLAN), or tunneling (through VXLAN or GRE). Network traffic is isolated within each tenant network. Each tenant network has an IP subnet associated with it, and network namespaces means that multiple tenant networks can use the same address range without causing conflicts."
	[Storage]="Block Storage, NFS, iSCSI, and others. Ideally, this would be isolated to an entirely separate switch fabric for performance reasons."
	[Storage_Mgmt]="OpenStack Object Storage (swift) uses this network to synchronize data objects between participating replica nodes. The proxy service acts as the intermediary interface between user requests and the underlying storage layer. The proxy receives incoming requests and locates the necessary replica to retrieve the requested data. Services that use a Ceph backend connect over the Storage Management network, since they do not interact with Ceph directly but rather use the frontend service. Note that the RBD driver is an exception, as this traffic connects directly to Ceph."
	[External]="Hosts the OpenStack Dashboard (horizon) for graphical system management, the public APIs for OpenStack services, and performs SNAT for incoming traffic destined for instances. If the external network uses private IP addresses (as per RFC-1918), then further NAT must be performed for traffic originating from the internet."
	[FloatingIP]="Allows incoming traffic to reach instances using 1-to-1 IP address mapping between the floating IP address, and the IP address actually assigned to the instance in the tenant network. If hosting the Floating IPs on a VLAN separate from External, you can trunk the Floating IP VLAN to the Controller nodes and add the VLAN through Neutron after Overcloud creation. This provides a means to create multiple Floating IP networks attached to multiple bridges. The VLANs are trunked but are not configured as interfaces. Instead, neutron creates an OVS port with the VLAN segmentation ID on the chosen bridge for each Floating IP network."
	[Management]="Provides access for system administration functions such as SSH access, DNS traffic, and NTP traffic. This network also acts as a gateway for non-Controller nodes."
)

error () {
	local -i rc=$1
	shift
	echo "ERROR($rc): $@">&2
	exit $rc
}

ask () {
	local r=''
	while :; do
		read -p 'Is it clear? ' r < /dev/tty
		case "$r" in
		y*|Y*)	echo "Good..."; return;;
		n*|N*)	error 1 "Too bad.";;
		*)	echo 'Yes or No?'; continue;;
		esac
	done
}

echo "You have choosen this config:" >&2
cat -n "$choice" >&2
ask

echo "You have to think of this network layout:">&2
for nt in "${!nets[@]}"; do
	who="${access[$nt]}"
	trg="${nets[$nt]}"

	[ "$who" = 'All' ] || who="{$who}"

	echo
	echo "* Network '$nt' available for $who nodes"
	fold -w 72 -s <<<"$trg" | sed -e '1,$s/^/|\t/'
	echo
	ask
done >&2

fold -s >&2 <<-EOT
	You may get around with only 2 interfaces in 2 VLANs as

	<Flat Network with External Access>

	Net 1: Provisioning, Internal API, Storage, Storage Management, Tenant Networks
	Net 2: External, Floating IP (mapped after Overcloud creation) 

	or you'll end up with <Isolated Networks> that will cost you 3 interfaces in 7 VLANs.
EOT

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
