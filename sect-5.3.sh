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
	ironic node-list \
	| tr -d '[ \t]' \
	| cut -d\| -f2 \
	| grep '^[a-f0-9]\+-....-....-....-[a-f0-9]\+$'
}

assign_node_profile () {
	local node="$1"
	local prf="$2"

	run ironic node-update "$node" \
		add properties/capabilities="profile:$prf,boot_option:local"
}

for node in $(node_list); do
	echo "Looking at node '$node'...">&2
	ironic node-show "$node"
	assign_node_profile "$node" 'compute'
done



echo "You're done." >&2
echo >&2

# EOF #
