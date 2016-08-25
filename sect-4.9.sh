#!/bin/bash

echo "⁠4.9. Backing Up the Undercloud">&2
echo >&2

# This section has been moved to the separate document set at
# https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/back-up-and-restore-red-hat-openstack-platform/back-up-and-restore-red-hat-openstack-platform

# Full backup includes:
# 1. All MariaDB databases on the undercloud node
# 2. MariaDB configuration file on the undercloud (so that you can accurately restore databases)
# 3. All glance image data in /var/lib/glance/images
# 4. All swift data in /srv/node
# 5. All data in the stack user home directory: /home/stack
# 6. All data in /opt/stack 

# For restoration process plz refer to
# https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/single/back-up-and-restore-red-hat-openstack-platform/#restore

BackupBase='/root/openstack-backup' # NOTE: Backup size is above 3.5GB!
# actually 8GB data are packed into 4GB tgz
sizeLimit=40 # in GB*10, i.e. 3.5GB becomes 35

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

if sudo test -d "$BackupBase/."; then
	: ok
else
	if mkdir -p "$BackupBase" >/dev/null 2>&1; then
		:
	else
		sudo mkdir -p "$BackupBase"
	fi
	sudo test -d "$BackupBase/." || error 1 "Cannot create '$BackupBase'."
fi

freeSpace=$(sudo df -kP "$BackupBase" | awk 'NR==2{print $4;}') # in KiB
echo "Free space in '$BackupBase' is ${freeSpace}KiB.">&2
freeGB0=$(( (freeSpace >> 20) * 10 ))
(( freeGB0 < sizeLimit )) && error 1 "Too few free space ${freeSpace}KiB."
echo >&2

sqlBackup="${BackupBase}/undercloud-all-databases-`date +%F`.sql"


echo "MySQL dump start ($(date '+%F %T'))" >&2
t1=$SECONDS

run sudo mysqldump --opt --all-databases | sudo tee "$sqlBackup" > /dev/null

t2=$SECONDS
echo "MySQL dump completed in $((t2 - t1)) seconds.">&2
echo >&2
echo "tar archiving start ($(date '+%F %T'))" >&2
t2=$SECONDS

run sudo tar -czf "$BackupBase/undercloud-backup-`date +%F`.tar.gz" \
	/etc/my.cnf.d/server.cnf "$sqlBackup" \
	/var/lib/glance/images \
	/srv/node \
	"$home" \
	/etc/keystone/ssl \
	/opt/stack

t3=$SECONDS
echo "tar completed in $((t3 - t2)) seconds.">&2
echo "Backup completed ($(date '+%F %T')) in $((t3 - t1)) seconds." >&2

sudo rm -f "$sqlBackup"
sudo ls -lhtr "$BackupBase/"

# EOF #
