#!/bin/bash
echo 'Chapter 5. Configuring Basic Overcloud Requirements'>&2
echo '5.4. Defining the Root Disk for Nodes'>&2
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

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)

[ -f /etc/ironic-inspector/inspector.conf ] || error 1 "No /etc/ironic-inspector/inspector.conf"


fresh=no
[ -d swift-data ] || { fresh=yes; mkdir -p swift-data || error $? "Cannot mkdir swift-data."; }
cd swift-data || error $? "Cannot chdir swift-data."

node_list () {
	ironic node-list --fields uuid | grep -wo '[0-9a-f][0-9a-f-]\+'
}

ironic_discover_pswd () {
	sudo grep admin_password /etc/ironic-inspector/inspector.conf \
	| awk '! /^#/ {print $NF}'
}

fetch_inspector_data () {
	local IRONIC_DISCOVERD_PASSWORD=`ironic_discover_pswd`
	local node

	for node in $(node_list); do
		swift -U service:ironic -K "$IRONIC_DISCOVERD_PASSWORD" \
			download ironic-inspector "inspector_data-$node"
	done
}

verify_inspector_data () {
	local node="$1"

	echo "NODE: $node"
	ls -lh "inspector_data-$node"
	jq '.inventory.disks' < "inspector_data-$node"
}

get_first () {
	local field="$1"
	local node="$2"
	jq '.inventory.disks' < "inspector_data-$node" \
	| grep -wom1 "\"$field\":[[:space:]]*\"[^\"]\\+\""
}

# Use only these fields to identify disk:
#    model (String): Device identifier.
#    vendor (String): Device vendor.
#    serial (String): Disk serial number.	<< DEFAULT
#    wwn (String): Unique storage identifier.
#    hctl (String): Host:Channel:Target:Lun for SCSI.
#    size (Integer): Size of the device in GB. 
FIELD=serial

assign_root_device () {
	local node="$1"
	local dev=$(get_first $FIELD "$node")

	run ironic node-update "$node" add "properties/root_device={$dev}"
}

assign_root_devices () {
	local node

	for node in $(node_list); do
		verify_inspector_data "$node"
		assign_root_device "$node"
	done
}

if [ "$fresh" = 'yes' -o "$1" = 'refresh' ]; then
	fetch_inspector_data
	assign_root_devices
else
	echo "Data already fetched." >/dev/tty
fi

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
