#!/bin/bash
echo 'Chapter 4. Installing the Undercloud'>&2
echo '4.3. Setting the Hostname for the System'>&2
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

confirm () {
	local r=''
	local prompt="> $@? "
	while :; do
		read -p "$prompt" r < /dev/tty
		case "$r" in
		y*|Y*)	return 0;;
		n*|N*)	return 1;;
		*)	echo "Yes or No?" >/dev/tty;;
		esac
	done
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)

echo "You now have hostname of '$(hostname)' (FQDN as '$(hostname -f)')."
if confirm "Would you like to change it"; then
	while :; do
		read -p "New hostname FQDN: " newhn
		confirm "Use '$newhn' as hostname" && break
	done
	run sudo hostnamectl set-hostname "$newhn"
	run sudo hostnamectl set-hostname --transient "$newhn"
else
	echo "Good.">&2
fi

host=$(hostname)
fqdn=$(hostname -f)

me=''
if [ -f /etc/hosts ] && grep -q '^127.0.0.1[[:space:]]\+' /etc/hosts; then
	me=$(grep '^127.0.0.1[[:space:]]\+' /etc/hosts)
	grep -qw "$host" <<<"$me" \
		|| run sudo sed -e '/^127.0.0.1/s/^.*$/& '"$host"'/' -i /etc/hosts \
		|| error $? "Cannot edit /etc/hosts (1)."
	grep -qw "$fqdn" <<<"$me" \
		|| run sudo sed -e '/^127.0.0.1/s/^.*$/& '"$fqdn"'/' -i /etc/hosts \
		|| error $? "Cannot edit /etc/hosts (2)."
else
	echo -e "127.0.0.1\tme locahost $host $fqdn" | run sudo tee -a /etc/hosts \
		|| error $? "Cannot add a line to /etc/hosts."
fi
run sudo vi /etc/hosts

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
