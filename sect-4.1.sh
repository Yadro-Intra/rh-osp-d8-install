#!/bin/bash
echo 'Chapter 4. Installing the Undercloud'>&2
echo '4.1. Creating a Director Installation User'>&2
echo ''>&2

shell=/bin/bash
home=/home/stack

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
		read -p "Run [$p] " r < /dev/tty
		case "$r" in
		c*|C*)	error 0 "Cancelled";;
		a*|A*)	error 0 "Aborted.";;
		n*|N*)	echo "Skipped.">&2; return 0;;
		y*|Y*)	;;
		esac
	fi
	"$@"
}

[ -w /etc/passwd ] || error 1 "Run me as root!"

run useradd -m -s "$shell" -d "$home" -c 'OpenStack' stack || error $? "Cannot add user 'stack'."

echo "You have to set/change password to user 'stack' now." >&2
run passwd stack

echo "stack ALL=(root) NOPASSWD:ALL" | run tee -a /etc/sudoers.d/stack \
	|| error $? "Cannot add 'stack' to sudoers."
run chmod 0440 /etc/sudoers.d/stack || error $? "Cannot chmod sudoers file."

echo ''>&2
echo 'Ok, from now and on you MUST run commands as user "stack"!'>&2
echo ''>&2

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
