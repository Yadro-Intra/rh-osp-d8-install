#!/bin/bash
echo 'Chapter 4. Installing the Undercloud'>&2
echo "4.7. Obtaining Images for Overcloud Nodes">&2
echo >&2

# This page https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/47-obtaining-images-for-overcloud-nodes
# is missing from the official site. I dunno why.
# Use https://webcache.googleusercontent.com/search?q=cache:hlZLmD88FjgJ:https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/paged/director-installation-and-usage/47-obtaining-images-for-overcloud-nodes+&cd=1&hl=en&ct=clnk&gl=ru&client=ubuntu instead.

error () {
	local -i rc=$1
	shift
	echo "ERROR($rc): $@">&2
	exit $rc
}

run () {
	local r='' p="$@"
	read -p "Run [$p] " r
	case "$r" in
	c*|C*)	error 0 "Cancelled";;
	a*|A*)	error 0 "Aborted.";;
	n*|N*)	echo "Skipped.">&2; return 0;;
	y*|Y*)	;;
	esac
	"$@"
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)

run sudo yum -y install rhosp-director-images rhosp-director-images-ipa

[ -d "$home/images/." ] || { mkdir -p "$home/images" || error 1 "Cannot mkdir '$home/images'."; }
cd "$home/images" || error $? "Cannot chdir to '$home/images'."

for tar in /usr/share/rhosp-director-images/overcloud-full-latest-8.0.tar \
	/usr/share/rhosp-director-images/ironic-python-agent-latest-8.0.tar
do
	run cp -v "$tar" . || error $? "Cannot copy '$tar'."
	run tar -xf "$tar" || error $? "Cannot untar '$tar'."
done

run openstack overcloud image upload --image-path "$home/images/" \
	|| error $? "Cannot upload images."

openstack image list
for img in	bm-deploy-kernel bm-deploy-ramdisk \
		overcloud-full overcloud-full-initrd \
		overcloud-full-vmlinuz
do
	openstack image list | grep -wq "$img" && echo "'$img' ok" || error 1 "No '$img' image."
done >&2

echo "Check for discovery-ramdisk images in the list below:">&2
ls -la /httpboot/

# EOF #
