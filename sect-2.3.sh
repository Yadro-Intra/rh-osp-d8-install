#!/bin/bash
echo 'Chapter 2. Requirements'>&2
echo '2.3. Networking Requirements'>&2
echo ''>&2

error () {
	local -i rc=$1
	shift
	echo "ERROR($rc): $@">&2
	exit $rc
}

run () {
	local r='' p="$@"

	if [ "$NOPAUSE" = 'yes' ]; then
		echo "Run [$p] (no pause)">&2
	else
		read -p "Run [$p] " r
		case "$r" in
		c*|C*)	error 0 "Cancelled";;
		a*|A*)	error 0 "Aborted.";;
		n*|N*)	echo "Skipped.">&2; return 0;;
		y*|Y*)	;;
		esac
	fi
	"$@"
}

fold -s >&2 <<EOT
 The Undercloud host requires at least two networks:

    Provisioning Network - This is a private network the director uses to provision and manage the Overcloud nodes. The Provisioning network provides DHCP and PXE boot functions to help discover bare metal systems for use in the Overcloud. This network must use a native VLAN on a trunked interface so that the director serves PXE boot and DHCP requests. This is also the network you use to control power management through Intelligent Platform Management Interface (IPMI) on all Overcloud nodes.

    External Network - A separate network for remote connectivity to all nodes. The interface connecting to this network requires a routable IP address, either defined statically, or dynamically through an external DHCP service. 

See you soon in section 3.2 :)
EOT
exit

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
