#!/bin/bash

echo "⁠5.2. Inspecting the Hardware of Node">&2
echo >&2

# Looks like no action required here.

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

ironic node-list

bulk_introspection () {
	echo "Run 'sudo journalctl -l -u openstack-ironic-inspector" \
		"-u openstack-ironic-inspector-dnsmasq" \
		"-u openstack-ironic-conductor -f' in a next window now..." >&2

	run openstack baremetal introspection bulk start && { echo "Done.">&2; exit 0; }
}

introspect_node () {
	local uuid="$1"

	ironic node-set-maintenance --reason '5.2 stage' "$uuid" true || return 1
	echo "Node '$uuid' locked ok.">&2
	echo "Which method to use?" >/dev/tty
	select r in ; do
		case "$r" baremetal ironic in
		baremetal) run openstack baremetal introspection start "$uuid"; break;;
		ironic) run ironic node-set-provision-state "$uuid" inspect; break;;
		esac
	done
	read -p 'Type <RETURN> to continue when done...'
	ironic node-set-maintenance "$uuid" false && echo "Node '$uuid' unlocked ok.">&2
}

node_list () {
	ironic node-list \
	| tr -d '[ \t]' \
	| cut -d\| -f2 \
	| grep '^[a-f0-9]\+-....-....-....-[a-f0-9]\+$'
}

one_by_one_introspectoin () {
	local node

	for node in $(node_list); do
		echo "Looking at node '$node'...">&2
		ironic node-show "$node" \
			--fields uuid driver_info provision_state last_error power_state
		run introspect_node "$node" || { echo "Node locked.">&2; continue; }
	done
}

select r in bulk one-by-one list-again; do
	case "$r" in
	bulk)	bulk_introspection; break;;
	one-by-one)	one_by_one_introspectoin; break;;
	list-again)	ironic node-list;;
	esac
done

ironic node-list 
echo "You're done." >&2
echo >&2

# EOF #
