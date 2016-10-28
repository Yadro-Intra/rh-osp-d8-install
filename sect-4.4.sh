#!/bin/bash
echo 'Chapter 4. Installing the Undercloud'>&2
echo '4.4. Registering your System'>&2
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

ask_for () {
	local r='' ans=''
	local prompt="> $@: "
	while :; do
		read -p "$prompt" ans < /dev/tty
		read -p "Use '$ans'? " r </dev/tty
		case "$r" in
		y*|Y*)	echo "$ans"; return 0;;
		n*|N*)	continue;;
		*)	echo "Yes or No?" >/dev/tty;;
		esac
	done
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)

sudo subscription-manager status
echo "To be honest, I don't thing it is still unregistered. But anyway...">&2

run sudo subscription-manager register

smlst=$(mktemp --tmpdir=/var/tmp/)
sudo subscription-manager list --available --all >"$smlst"
pool_id=-
while [ "$pool_id" = '-' ]; do
	less "$smlst"
	pool_id=$(ask_for "RH subscription pool ID (dash to re-list)")
	[ -z "$pool_id" ] && error 1 "Go ask for your Pool ID first."
done
rm -f "$smlst"

repos_cur=/etc/yum.repos.d/redhat.repo
repos_old=redhat.repo.save

[ -e "$repos_cur" ] || { sudo touch "$repos_cur" || error $? "Cannot create '$repos_cur'."; }
cp -v "$repos_cur" "$repos_old" || error $? "Cannot save '$repos_cur' to '$repos_old'."

run sudo subscription-manager attach --pool="$pool_id" \
	|| error $? "Cannot attach to pool '$pool_id'."

run sudo subscription-manager repos --disable=* # no deafult repos
run sudo subscription-manager repos \
	--enable=rhel-7-server-rpms \
	--enable=rhel-7-server-extras-rpms \
	--enable=rhel-7-server-openstack-8-rpms \
	--enable=rhel-7-server-openstack-8-director-rpms \
	--enable=rhel-7-server-rh-common-rpms

diff -u "$repos_old" "$repos_cur" | less

run sudo yum update -y
run sudo reboot

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
