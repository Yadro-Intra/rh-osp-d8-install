#!/bin/bash
echo 'Chapter 5. Configuring Basic Overcloud Requirements'>&2
echo '5.5. Completing Basic Configuration'>&2
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

clear
cat >/dev/tty <<-EOT


You have to perform at least something from 6.7-6.9
to NOT use local LVM storage for block storage.

C'est la vie.		AKA "shit happens" (C) Wikipedia :)


EOT

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
