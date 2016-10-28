#!/bin/bash

scriptDir=$(realpath `dirname $0`)
dryRun=no

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
		[ "$dryRun" = 'yes' ] && { echo ' (dry)'; return 0; }
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

flavors () {
	openstack flavor list -f csv -c ID -c Name --quote minimal \
	| sed -e '1d' | cut -d, -f2
}

help () {
	local exe="$1"
	cat <<-EOT

		$exe [-h|--help | -n|--dry-run | -u|--update]

		If not 'dry run', the do the job, else just validate.
		If not 'update', then do deploy.

		NOTE: If validated ok, then the job still may fail!

	EOT
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)
xenv="$home/overcloud-extra-env.list"
choice="$home/choice.my"

[ -f "$choice" ] || error 1 "No choice file. Start with section 3.1."
[ -f "$xenv" ] || error 1 "No overcloud extra env list. Do it yourself."

case "$1" in
-h|--help)	help "$0"; exit 0;;
esac

while :; do
	echo "==========<$xenv>==========">/dev/tty
	grep -v '#' <"$xenv" | cat -n >/dev/tty
	confirm "Do you want to edit '$xenv'? " || break
	edit "$xenv"
done

declare -a args=()

echo "Extra custom templates will be used:">/dev/tty
while read line; do
	[ -f "$line" ] || { echo "No template '$line' - skipped.">/dev/tty; continue; }
	n=$(basename "$line")
	l=$(where_was "$n")
	[ -z "$l" ] && l='manually added' || l="sections: $l"
	printf '%3d %s (%s); ' $(( ${#args[*]} + 1 )) "$line" "$l" >/dev/tty
	confirm "Use it? " && args[${#args[*]}]="-e $line"
done < <(grep -v '#' <"$xenv")
echo "Templates listed and found: ${#args[*]}">/dev/tty


while IFS=':' read name value; do
	case "$name" in
	InstallType) echo "$name: $value">/dev/tty;;
	Controller) args[${#args[*]}]="--control-scale $value";; # 1
	Compute) args[${#args[*]}]="--compute-scale $value";; # 1
	Ceph) args[${#args[*]}]="--ceph-storage-scale $value";; # 0
	Swift) args[${#args[*]}]="--swift-storage-scale $value";; # 0
	Cinder) args[${#args[*]}]="--block-storage-scale $value";; # 0
	*)	error 1 "Wrong '$name' in '$choice' file.";;
	esac
done < "$choice"

echo "Validating deployment...">/dev/tty
openstack overcloud deploy \
	--dry-run \
	--validation-errors-fatal \
	--validation-warnings-fatal \
	--templates ${args[*]} \
	|| error $? "Validation error."

OP=''
ARGS=''
STACK=''

while [ -n "$1" ]; do
	case "$1" in
	-n|--dry-run)	dryRun=yes;;
	-u|--update)	OP='update stack'; ARGS='--interactive'; STACK='overcloud';;
	*)		error 1 "WTF '$1'?";;
	esac
	shift
done
[ -z "$OP" ] && OP=deploy

if [ "$OP" = 'deploy' ]; then
	# In 6.3.1 we read:
	# # Node placement takes priority over profile matching.
	# # To avoid scheduling failures, use the default baremetal flavor for deployment
	# # and not the flavors designed for profile matching (compute, control, etc).
	# so...
	echo "Calculating extra args...">/dev/tty
	FORCE_FLAVOR=baremetal
	flavors | grep -q '^'"$FORCE_FLAVOR"'$' || error 1 "Cannot force '$FORCE_FLAVOR' flavor."
	for k in control compute ceph-storage block-storage swift-storage; do
		args[${#args[*]}]="--$k-flavor $FORCE_FLAVOR"
	done
fi

echo "About to execute...">/dev/tty
run openstack overcloud $OP $ARGS --templates ${args[*]} $STACK

echo ''>&2
# EOF #
