#!/bin/bash
echo 'Chapter 6. Configuring Advanced Customizations for the Overcloud'>&2
echo '6.10. Configuring the Overcloud Time Zone'>&2
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

tzFile=timezone.yaml

while :; do
	read -p 'Do you want to leave it UTC? '
	case "$REPLY" in
	n*|N*)	break;;
	y*|Y*)	echo 'Ok, left intact.'>/dev/tty; exit 0;;
	esac
	echo 'Yes or No!'>/dev/tty
done

while :; do
	terra=''
	locus=''
	select terra in $(ls -1 /usr/share/zoneinfo/); do
		[ -z "$terra" ] && continue
		select locus in $(ls -1 /usr/share/zoneinfo/$terra/); do
			[ -n "$locus" ] && break
		done
		break
	done
	while :; do
		read -p "[$terra/$locus]? "
		case "$REPLY" in
		y*|Y*)	REPLY=yes; break;;
		n*|N*)	REPLY=no; break;;
		*) echo 'Yes or No!'>/dev/tty;;
		esac
	done
	[ "$REPLY" = 'yes' ] && break
done
echo "[$terra/$locus]" >/dev/tty

{
	echo 'parameter_defaults:'
	echo "  TimeZone: '$terra/$locus'"
} > "$tzFile"

cat -nA "$tzFile"

if ! grep -q "^$tzFile"'$' "$home/overcloud-extra-env.list"; then
	echo "$tzFile" >> "$home/overcloud-extra-env.list"
fi

while :; do
	read -p 'Do you want to START OVERCLOUD DEPLOYMENT RIGHT NOW to apply TZ change? '
	case "$REPLY" in
	n*|N*)	break;;
	y*|Y*)	echo 'Ok, left intact.'>/dev/tty; exit 0;;
	esac
	echo 'Yes or No!'>/dev/tty
done

run openstack overcloud deploy --templates -e "$tzFile"

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
