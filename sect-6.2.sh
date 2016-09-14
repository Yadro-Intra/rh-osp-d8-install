#!/bin/bash
echo 'Chapter 6. Configuring Advanced Customizations for the Overcloud'>&2
echo '6.2. Isolating Networks'>&2
echo ''>&2

hotDir=/usr/share/openstack-tripleo-heat-templates
netDir="$hotDir/network"
envDir="$hotDir/environments"
portDir="$netDir/ports"
netConfDir="$netDir/config"

declare -a netenvs=(
	net-single-nic-with-vlans
	net-single-nic-with-vlans-no-external
	net-single-nic-with-vlans-v6
	net-bond-with-vlans
	net-bond-with-vlans-no-external
	net-bond-with-vlans-v6
	net-multiple-nics
	net-multiple-nics-v6
	net-single-nic-linux-bridge-with-vlans
)

declare -a nets=(
	management
	storage_mgmt
	internal_api
	storage
	tenant
	external
	vip
	noop
)

declare -a netconfs=(
	single-nic-vlans
	bond-with-vlans
	multiple-nics
	single-nic-linux
)

error () {
	local -i rc=$1
	shift
	echo "ERROR($rc): $@">/dev/tty
	exit $rc
}

warn () {
	echo "WARNING: $@" >/dev/tty
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

xls () {
	local dirname="$1" ; shift
	local suffix="$1"  ; shift

	( cd "$dirname/." && ls -1 $@; ) \
	| { [ -n "$suffix" ] && grep '\.'"$suffix"'$' || cat; } \
	| sed -e '1,$s/\.'"$suffix"'$//'
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)

if [ "$1" = 'reset' ]; then
	[ -d templates/. ] && rm -rf templates
	exit $?
fi

tplDir="$home/templates"
netenv="$tplDir/network-environment.yaml"
nicCfg="$tplDir/nic-configs"
ctlNic="$nicCfg/controller.yaml"

[ -d "$hotDir/." ] || error 1 "No dir '$hotDir'."
[ -d "$envDir/." ] || error 1 "No dir '$envDir'."
[ -d "$netDir/." ] || error 1 "No dir '$netDir'."
[ -d "$netConfDir/." ] || error 1 "No dir '$netConfDir'."
[ -d "$portDir/." ] || error 1 "No dir '$potDir'."

[ -d "$tplDir/." ] || { mkdir -p "$tplDir" || error $? "Cannot mkdir '$tplDir'."; }
[ -d "$nicCfg/." ] || { mkdir -p "$nicCfg" || error $? "Cannot mkdir '$nicCfg'."; }

echo '6.2.1. Creating Custom Interface Templates'>&2
[ -f "$ctlNic" ] || { touch "$ctlNic" || error $? "Cannot touch '$ctlNic'."; }
for dname in ${netconfs[*]}; do
	[ -d "$netConfDir/$dname/." ] || warn "No dir '$netConfDir/$dname'."
done
select name  in $(xls "$netConfDir"); do
	[ -n "$name" ] && { run cp -rv "$netConfDir/${name}" "$nicCfg"; break; }
	echo "No template selected -- an empty env left intact.">/dev/tty
	break
done
NIC_THEME=$name
echo "Check your '$ctlNic' config..." >/dev/tty
ls -l "$ctlNic"
echo ''>&2

echo '6.2.2. Creating a Network Environment File'>&2
[ -f "$netenv" ] || { touch "$netenv" || error $? "Cannot touch '$netenv'."; }
for fname in ${netenvs[*]}; do
	[ -f "$envDir/${fname}.yaml" ] || warn "No file '$envDir/${fname}.yaml'."
done
select name in $(xls "$envDir" yaml net-${NIC_THEME}*); do
	[ -n "$name" ] && { run cp -v "$envDir/${name}.yaml" "$netenv"; break; }
	echo "No template selected -- an empty env left intact.">/dev/tty
	break
done
NET_ENV=$name
echo "Check your '$netenv' config..." >/dev/tty
ls -l "$netenv"
echo ''>&2
echo ''>&2
echo "You've chosen '$NIC_THEME' and '$NET_ENV'...">&2
echo ''>&2

echo '6.2.3. Assigning OpenStack Services to Isolated Networks'>&2
echo "Check your '$netenv' config..." >/dev/tty
ls -l "$netenv"
echo ''>&2

echo '6.2.4. Selecting Networks to Deploy'>&2
[ -f "$hotDir/environments/network-isolation.yaml" ] \
	|| error 1 "No file '$hotDir/environments/network-isolation.yaml'."
for fname in ${nets[*]}; do
	[ -f "$portDir/${fname}.yaml" ] || warn "No file '$portDir/${fname}.yaml'."
done
select name in ${nets[*]}; do
	[ -n "$name" ] && echo "You've chosen '$name'. Sorry, I cannot do it for you." || \
	echo "No template selected -- an empty env left intact.">/dev/tty
	break
done
echo ''>&2

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
