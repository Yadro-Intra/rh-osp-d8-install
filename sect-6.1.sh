#!/bin/bash
echo 'Chapter 6. Configuring Advanced Customizations for the Overcloud'>&2
echo '6.1. Understanding Heat Templates'>&2
echo ''>&2
echo ''>&2
echo '<<< THESE ARE OPTIONAL >>>'>&2
echo ''>&2

hotDir=/usr/share/openstack-tripleo-heat-templates

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

[ -d "$hotDir/." ] || error 1 "No dir '$hotDir'."

echo '6.1.1. Heat Templates'>&2
run heat stack-list --show-nested
echo ''>&2

echo '6.1.2. Environment Files'>&2
for dname in environments; do
	[ -d "$hotDir/$dname/." ] || error 1 "No dir '$hotDir/$dname'."
	ls -lh "$hotDir/$dname/"
done
echo ''>&2

echo '6.1.3. Core Overcloud Heat Templates'>&2
for fname in overcloud.yaml overcloud-resource-registry-puppet.yaml; do
	[ -f "$hotDir/$fname" ] || error 1 "No file '$hotDir/$fname'."
	( cd "$hotDir/." && ls -lh "$fname"; )
done

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
