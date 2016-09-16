#!/bin/bash

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
xenv="$home/overcloud-extra-env.list"

[ -f "$xenv" ] || error 1 "No overcloud extra env list. Do it yourself."

declare -a args=()

while read line; do
	[ -f "$line" ] || { echo "No template '$line' - skipped.">/dev/tty; continue; }
	args[${#args[*]}]="-e '$line'"
	printf '%3d %s\n' ${#args[*]} "$line" >/dev/tty
done < "$xenv"
echo "Templates listed and found: $i">/dev/tty

# In 6.3.1 we read:
# # Node placement takes priority over profile matching.
# # To avoid scheduling failures, use the default baremetal flavor for deployment
# # and not the flavors designed for profile matching (compute, control, etc).
# so...
FORCE_FLAVOR=baremetal
for k in control compute ceph-storage block-storage swift-storage; do
	args[${#args[*]}]="--$k-flavor $FORCE_FLAVOR"
done

N=''
case "$1" in
-n|--dry-run)	N='--dry-run';;
esac

openstack overcloud deploy --dry-run --validation-errors-fatal --validation-warnings-fatal \
	--templates ${args[*]} || error $? "Validation error."
[ -n "$N" ] && exit 0

run openstack overcloud deploy --templates ${args[*]}

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
