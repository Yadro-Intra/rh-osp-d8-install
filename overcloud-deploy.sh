#!/bin/bash

scriptDir=$(realpath `dirname $0`)

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

where_was () {
	local text="$1" e=''

	while read e; do
		basename "$e" .sh | cut -d- -f2
	done < <(grep -l "$text" $scriptDir/sect-*.sh)
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)
xenv="$home/overcloud-extra-env.list"

[ -f "$xenv" ] || error 1 "No overcloud extra env list. Do it yourself."

declare -a args=()

echo "Extra custom templates will be used:">/dev/tty
while read line; do
	[ -f "$line" ] || { echo "No template '$line' - skipped.">/dev/tty; continue; }
	args[${#args[*]}]="-e '$line'"
	n=$(basename "$line")
	l=$(where_was "$n")
	[ -z "$l" ] && l='manually added' || l="sections: $l"
	printf '%3d %s (%s)\n' ${#args[*]} "$line" "$l" >/dev/tty
done < "$xenv"
echo "Templates listed and found: ${#args[*]}">/dev/tty

# In 6.3.1 we read:
# # Node placement takes priority over profile matching.
# # To avoid scheduling failures, use the default baremetal flavor for deployment
# # and not the flavors designed for profile matching (compute, control, etc).
# so...
FORCE_FLAVOR=baremetal
for k in control compute ceph-storage block-storage swift-storage; do
	args[${#args[*]}]="--$k-flavor $FORCE_FLAVOR"
done

echo "Validating deployment...">/dev/tty
openstack overcloud deploy --dry-run --validation-errors-fatal --validation-warnings-fatal \
	--templates ${args[*]} || error $? "Validation error."

N=''
case "$1" in
-n|--dry-run)	N='--dry-run';;
esac

[ -n "$N" ] && exit 0

run openstack overcloud deploy --templates ${args[*]}

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
