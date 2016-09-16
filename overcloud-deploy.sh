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

	{
		echo -n "Run ["
		echo -n "$p" | sed -e '1,$s/ -/ \\\n\t-/g'
		echo -n "]"
	}>/dev/tty

	if [ "$NOPAUSE" = 'yes' ]; then
		echo " (no pause)">/dev/tty
	else
		read -p "? " r </dev/tty
		case "$r" in
		c*|C*)	error 0 "Cancelled";;
		a*|A*)	error 0 "Aborted.";;
		n*|N*)	echo "Skipped."; return 0;;
		y*|Y*)	;;
		esac
	fi >/dev/tty
	"$@"
}

confirm () {
        local rep=''
        local prompt='Press <RETURN> to continue...'
        [ -n "$1" ] && prompt="$@"
        while :; do
                read -p "$prompt" rep </dev/tty
                case "$rep" in
                y*|Y*) return 0;;
                n*|N*) return 1;;
                *) echo "Yes or No?">/dev/tty;;
                esac
        done
}

edit () {
        local e="$VISUAL"
        [ -z "$e" ] && e="$EDITOR"
        [ -z "$e" ] && e=vi
        "$e" "$@"
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
confirm "Do you want to edit '$xenv'? " && edit "$xenv"

declare -a args=()

echo "Extra custom templates will be used:">/dev/tty
while read line; do
	[ -f "$line" ] || { echo "No template '$line' - skipped.">/dev/tty; continue; }
	n=$(basename "$line")
	l=$(where_was "$n")
	[ -z "$l" ] && l='manually added' || l="sections: $l"
	printf '%3d %s (%s)\n' $(( ${#args[*]} + 1 )) "$line" "$l" >/dev/tty
	confirm "Use it? " && args[${#args[*]}]="-e $line"
done < <(grep -v '#' <"$xenv")
echo "Templates listed and found: ${#args[*]}">/dev/tty

echo "Validating deployment...">/dev/tty
openstack overcloud deploy --dry-run --validation-errors-fatal --validation-warnings-fatal \
	--templates ${args[*]} || error $? "Validation error."

OP=''
ARGS=''
STACK=''
case "$1" in
'')		OP=deploy;;
-n|--dry-run)	exit 0;;
-u|--update)	OP='update stack'; ARGS='--interactive'; STACK='overcloud';;
esac

if [ "$OP" = 'deploy' ]; then
	# In 6.3.1 we read:
	# # Node placement takes priority over profile matching.
	# # To avoid scheduling failures, use the default baremetal flavor for deployment
	# # and not the flavors designed for profile matching (compute, control, etc).
	# so...
	FORCE_FLAVOR=baremetal
	for k in control compute ceph-storage block-storage swift-storage; do
		args[${#args[*]}]="--$k-flavor $FORCE_FLAVOR"
	done
fi

run openstack overcloud $OP $ARGS --templates ${args[*]} $STACK

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
