#!/bin/bash

echo "5.1. Registering Nodes for the Overcloud">&2
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

[ -z "$1" ] && error 1 "Use: $(basename $0) <JSON-file>"

json="$1"

[ -f "$json" ] || error 1 "No '$json' file."

if [ -n "$(type -p json_verify)" ]; then
	json_verify < "$json" || error 1 "File '$json' is not valid."
fi

run openstack baremetal instackenv validate -f "$json"
run openstack baremetal import --json "$json"
run openstack baremetal configure boot

ironic node-list

echo "You're done." >&2
echo >&2

# EOF #
