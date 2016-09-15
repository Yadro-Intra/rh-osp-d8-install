#!/bin/bash
echo 'Chapter 6. Configuring Advanced Customizations for the Overcloud'>&2
echo '6.3. Controlling Node Placement'>&2
echo ''>&2

declare -A role2hint=(
	[control]='ControllerSchedulerHints'
	[compute]='NovaComputeSchedulerHints'
	[block-storage]='BlockStorageSchedulerHints'
	[swift-storage]='ObjectStorageSchedulerHints'
	[ceph-storage]='CephStorageSchedulerHints'
)

hotDir='/usr/share/openstack-tripleo-heat-templates'
envDir="$hotDir/environments"
poolFile="$envDir/ips-from-pool-all.yaml"

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

node_role_list () {
	openstack overcloud profiles list \
		-f csv --quote minimal \
		-c 'Node UUID' \
		-c 'Node Name' \
		-c 'Current Profile' \
	| sed -e '1d' # cut off 1st line
}

node_properties () {
	local uuid="$1"
	ironic node-show "$uuid" --fields properties \
	| cut -d\| -f3 \
	| sed -e '1,3d' -e '$d' \
	| tr -d '[:space:]'
}

node_capabilities () {
	local uuid="$1"
	local dict=$(node_properties "$uuid")
	python2 -c "print(${dict}['capabilities'])"
}

node_set_caps () {
	local uuid="$1" ; shift
	local caps="$@"

	run ironic node-update "$uuid" replace properties/capabilities="$caps"
}

node_set_name () {
	local uuid="$1"
	local name="$2"
	local caps=$(node_capabilities "$uuid")

	if grep -q '\<node:' <<<"$caps"; then
		error 1 "Node '$uuid' already has 'node=' in '$caps'."
	else
		node_set_caps "$uuid" "node:$name,$caps"
	fi
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)

tplDir="$home/templates"
myPool=$tplDir/$(basename "$poolFile")

if [ "$1" = 'reset' ]; then
	rm -f "$myPool"
fi

echo '6.3.1. Assigning Specific Node IDs'>&2
declare -A counters=()
for entry in $(node_role_list); do
	uuid=$(cut -d, -f1 <<<"$entry")
	oldn=$(cut -d, -f2 <<<"$entry")
	role=$(cut -d, -f3 <<<"$entry")
	idx=${counters[$role]}
	[ -z "$idx" ] && { idx=0; counters[$role]=0; }

	[ -z "$oldn" ] && name="$role-$idx" || name="$oldn"
	echo "Node '$uuid' as '$role'[$idx] name '$name' was '$oldn'."
	node_set_name "$uuid" "$name"

	let idx++; counters[$role]=$idx
done
echo "Summary:"
for role in ${!counters[*]}; do
	printf '| %-32s: %d\n' "$role" ${counters[$role]}
done
cat >/dev/tty <<-EOT

	Now you may create/edit your Heat environment file (YAML)

EOT
echo "=======>8======"
echo "parameter_defaults:"
for role in ${!counters[*]}; do
	echo "  ${role2hint[$role]}:"
	echo "    'capabilities:node': '$role-%index%'"
done
echo "=======>8======"
echo ''>&2
echo '6.3.2. Custom Hostnames'>&2
cat >/dev/tty <<-EOT

	Now you may create/edit your Heat environment file (YAML).
	Use this as a hint (and see HostnameFormat to find rules):

EOT
echo "=======>8======"
echo "parameter_defaults:"
echo "  HostnameMap:"
for role in ${!counters[*]}; do
	cnt=${counters[$role]}
	for ((i=0; i<cnt; i++)); do
	echo "    overcloud-$role-$i: my-clever-$role-$i"
	done
done
echo "=======>8======"
echo ''>&2
echo '6.3.3. Assigning Predictable IPs'>&2
[ -d "$hotDir/." ] || error 1 "No dir '$hotDir'."
[ -d "$envDir/." ] || error 1 "No dir '$envDir'."
[ -f "$poolFile" ] || error 1 "No file '$poolFile'."

[ -d "$tplDir/." ] || { mkdir -p "$tplDir" || error $? "Cannot mkdir '$tplDir'."; }
[ -d "$tplDir/." ] || error 1 "No dir '$tplDir'."

run cp -v "$poolFile" "$myPool"
run sed -e '1,$s/: \.\.\//: '"${hotDir//\//\/}/" -i "$myPool"
if [ -f "$myPool" ]; then
	cat >/dev/tty <<-EOT

	Now you have to check/edit your $myPool file!

	EOT
	vi "$myPool"
fi
echo ''>&2

echo '6.3.4. Assigning Predictable Virtual IPs'>&2
if [ -f "$myPool" ]; then
	cat >/dev/tty <<-EOT

	Now you have to check/edit your $myPool file!

	1. add resource_registry: section to look like

  OS::TripleO::Network::Ports::NetVipMap: /usr/share/openstack-tripleo-heat-templates/network/ports/net_vip_map_external.yaml
  OS::TripleO::Network::Ports::ExternalVipPort: /usr/share/openstack-tripleo-heat-templates/network/ports/noop.yaml
  OS::TripleO::Network::Ports::InternalApiVipPort: /usr/share/openstack-tripleo-heat-templates/network/ports/noop.yaml
  OS::TripleO::Network::Ports::StorageVipPort: /usr/share/openstack-tripleo-heat-templates/network/ports/noop.yaml
  OS::TripleO::Network::Ports::StorageMgmtVipPort: /usr/share/openstack-tripleo-heat-templates/network/ports/noop.yaml
  OS::TripleO::Network::Ports::RedisVipPort: /usr/share/openstack-tripleo-heat-templates/network/ports/from_service.yaml

	2. then add parameter_defaults: with stuff like

  # Predictable VIPs
  ControlPlaneIP: 192.168.0.230
  ExternalNetworkVip: 10.1.1.190
  InternalApiNetworkVip: 172.16.0.30
  StorageNetworkVip: 172.18.0.30
  StorageMgmtNetworkVip: 172.19.0.40
  ServiceVips:
    redis: 172.16.0.31

	EOT
	read -p 'Press <RETURN> to continue...'
	vi "$myPool"
else
	echo "No way! You've missed step 6.3.3!" >/dev/tty
fi
echo ''>&2

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
