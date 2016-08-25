#!/bin/bash

echo "4.8. Setting a Nameserver on the Undercloud's Neutron Subnet">&2
echo >&2

error () {
	local -i rc=$1
	shift
	echo "ERROR($rc): $@">&2
	exit $rc
}

run () {
	local r='' p="$@"
	read -p "Run [$p] " r
	case "$r" in
	c*|C*)	error 0 "Cancelled";;
	a*|A*)	error 0 "Aborted.";;
	n*|N*)	echo "Skipped.">&2; return 0;;
	y*|Y*)	;;
	esac
	"$@"
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)

if [ -z "$1" ]; then
	cat <<-EOF >&2
	Use me as
	stack$ ./$(basename "$0") <DNS-address>
	You may use 8.8.8.8 or alike for that.
EOF
	error 1 "Run again."
fi

dns_ip="$1"

neutron subnet-list

snid=$(neutron subnet-list | head -n4 | tail -n1 | tr -d '[ \t]' | cut -d\| -f2)
[ -z "$snid" ] && error 1 "Cannot get SubNet ID."

neutron subnet-update "$snid" --dns-nameserver "$dns_ip" || error $? "Cannot set DNS IP to '$dns_ip'."

# If you aim to isolate service traffic onto separate networks,
# the Overcloud nodes use the DnsServer parameter in your network environment templates.
# This is covered in the advanced configuration scenario in
# Section 6.2.2, “Creating a Network Environment File”. 

# EOF #
