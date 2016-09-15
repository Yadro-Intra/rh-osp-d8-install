#!/bin/bash

echo "⁠5.3. Tagging Nodes into Profile">&2
echo >&2

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

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)

node_list () {
	ironic node-list --fields uuid | grep -wo '[0-9a-f][0-9a-f-]\+'
}

assign_node_profile () {
	local node="$1"
	local prf="$2"

	run ironic node-update "$node" \
		add properties/capabilities="profile:$prf"
}

# TFM says: 
# Default profile flavors compute, control, swift-storage, ceph-storage, and block-storage
# are created during Undercloud installation and are usable without modification in most
# environments.

nrules=$(openstack baremetal introspection rule list | grep -v '^[[:space:]]*$' | wc -l)
(( nrules == 0 )) && echo "You have no baremetal introspection rules defined." >/dev/tty \
		  || openstack baremetal introspection rule list

openstack overcloud profiles list

# I have no ceph-storage; 'boot_option:local' looks a must here.
declare roles=(
	'compute,boot_option:local'
	'control,boot_option:local'
	'swift-storage,boot_option:local'
	'block-storage,boot_option:local'
)

declare -i ri=0 # role index

# actually, I have 4 nodes and 4 roles, so...

for node in $(node_list); do
	role=${roles[$ri]}
	echo "Turning node '$node' into '$role' role...">&2
	assign_node_profile "$node" "$role"
	let ri+=1
done

openstack overcloud profiles list


echo "You're done." >&2
echo >&2

# EOF #
