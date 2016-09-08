#!/bin/bash
echo 'Chapter 2. Requirements'>&2
echo '2.1. Environment Requirements'>&2
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

show () {
	fold -s >&2
}

show <<EOT
Minimum Requirements:

    1 host machine for the Red Hat OpenStack Platform director
    1 host machine for a Red Hat OpenStack Platform Compute node
    1 host machine for a Red Hat OpenStack Platform Controller node 

Recommended Requirements:

    1 host machine for the Red Hat OpenStack Platform director
    3 host machines for Red Hat OpenStack Platform Compute nodes
    3 host machines for Red Hat OpenStack Platform Controller nodes in a cluster
    3 host machines for Red Hat Ceph Storage nodes in a cluster 

Note the following:

    It is recommended to use bare metal systems for all nodes. At minimum, the Compute nodes require bare metal systems.
    All Overcloud bare metal systems require an Intelligent Platform Management Interface (IPMI). This is because the director controls the power management. 

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
