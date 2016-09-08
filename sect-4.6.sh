#!/bin/bash
echo 'Chapter 4. Installing the Undercloud'>&2
echo '4.6. Configuring the Director'>&2
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
	time "$@"
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

backup () {
	local f="$1"
	local -i i=0

	[ -f "$f" ] || return
	for ((i = 0; i < 999999; i++)); do
		local s=$(printf '%06d' $i)
		[ -f "$f.$s" ] && continue
		cp -v "$f" "$f.$s"
		return $?
	done
	return 1
}

useful_lines () {
	local fn="$1"
	grep -v '^#' "$fn" | grep -v '^[[:space:]]*$'
}

validate () {
	local fn="$1"
	local -i n=0

	echo "This is your '$fn':"
	echo "# ------------------------------->8-------------------------------------"
	useful_lines "$fn" | cat -n >&2
	echo "# ------------------------------->8-------------------------------------"

	for term in undercloud_service_certificate local_interface image_path; do
		useful_lines "$fn" | grep -wq "$term" \
			|| { let n+=1; echo "No parameter '$term' defined.">&2; }
	done
	((n > 0)) && return 1

	local cert_path=$(grep '^undercloud_service_certificate' <"$fn" | cut -d= -f2)
	echo "cert_path='$cert_path'">&2

	cert_path=$(echo $cert_path)
	echo "cert_path='$cert_path'">&2

	[ -e "$cert_path" ] && return 0
	cert_path=$(dirname $cert_path)
	echo "cert_path='$cert_path'">&2
	[ -d "$cert_path/." ] && return 0
	run sudo mkdir -p "$cert_path/." 
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

scriptDir=$(realpath -e $(dirname "$0"))
certgen="$scriptDir/certgen.py"

cd ~stack || error $? "No home?"
home=$(pwd)

if service haproxy status; then
	:
else
	sudo yum install -y haproxy || error $? "Cannot install haproxy."
	sudo service haproxy restart || error $? "Cannot start haproxy."
fi

if confirm "New config"; then
	backup ~/undercloud.conf || error $? "Cannot backup ~/undercloud.conf"
	cp /usr/share/instack-undercloud/undercloud.conf.sample ~/undercloud.conf
	while :; do
		vim ~/undercloud.conf
		validate ~/undercloud.conf
		confirm "Run shell" && "$SHELL"
		confirm "Edit again" || break
	done
fi

validate ~/undercloud.conf || error $? "Bad undercloud.conf."

[ -x "$certgen" ] || error 1 "No helper script '$certgen'."
if confirm "Generate new certs"; then
	run sudo "$certgen" || error $? "Error running certificate generator."
else
	run sudo "$certgen" -t -d
fi

run openstack undercloud install

echo ''>&2
echo '!! DO NOT FORGET TO "source ~/stackrc" NOW !!'>&2
confirm "Is it clear" || error 1 "Argh"
echo ''>&2

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
