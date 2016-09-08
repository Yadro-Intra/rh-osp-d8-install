#!/bin/bash
echo 'Chapter 3. Planning your Overcloud'>&2
echo '3.1. Planning Node Deployment Roles'>&2
echo ''>&2

choice=choice.my

declare -A roles=(
	[Controller]="Provides key services for controlling your environment. This includes the dashboard (horizon), authentication (keystone), image storage (glance), networking (neutron), orchestration (heat), and high availability services (if using more than one Controller node). A basic Red Hat OpenStack Platform environment requires at least one Controller node."
	[Compute]="A physical server that acts as a hypervisor, and provides the processing capabilities required for running virtual machines in the environment. A basic Red Hat OpenStack Platform environment requires at least one Compute node."
	[Ceph]="A host that provides Red Hat Ceph Storage. Additional Ceph Storage hosts scale into a cluster. This deployment role is optional."
	[Swift]="A host that provides external object storage for OpenStack's Swift service. This deployment role is optional." 
	[Cinder]="A host that provides external block storage for OpenStack's cinder service. This deployment role is optional." 
)

declare -A types=( # ="Ctl Cmp Cph Swf Cnd Total"
	[Small Overcloud]="1 1 0 0 0 2"
	[Medium Overcloud]="1 3 0 0 0 4"
	[Medium Overcloud with additional Object and Block storage]="1 3 0 1 1 6"
	[Medium Overcloud with High Availability]="3 3 0 0 0 6"
	[Medium Overcloud with High Availability and Ceph Storage]="3 3 3 0 0 9"
)

error () {
	local -i rc=$1
	shift
	echo "ERROR($rc): $@">&2
	exit $rc
}

is_optional () {
	local sType="$1"
	local sRole="${roles[$sType]}"

	grep -q 'role is optional' <<<"$sRole"
}

set_choice () {
	local sType="$1"
	local nCnt="$2"

	if [ -f "$choice" ] && grep -wq "^$sType" "$choice"; then
		sed -e '/^'$sType':/d' -i "$choice"
	fi
	echo "$sType:$nCnt" >> "$choice"
}

explain () {
	local sType="$1"
	local nCnt="$2"
	local sRole="${roles[$sType]}"
	local r='' b=''

	if (( nCnt == 0 )); then
		is_optional "$sType" || error 1 "Oops. You must have a '$sType' box ($sRole)."
		echo "OK, no boxen required for '$sType'."
		set_choice "$sType" 0
	else
		echo >&2
		echo "===[ $sType ]===">&2
		echo >&2
		echo "$sRole">&2
		echo >&2
		(( $nCnt == 1 )) && b='box' || b='boxen'
		while :; do
			read -p "Do you have $nCnt $b for '$sType'? " r
			case "$r" in
			y*|Y*)	echo "Ok.">&2; set_choice "$sType" "$nCnt";;
			n*|N*)	error 1 "No way.";;
			*)	echo "Yes or No?" >&2; continue;;
			esac
			return
		done
	fi
}

get_type () {
	local t=''

	select t in "${!types[@]}"; do
		if [ -n "$t" ]; then
			set_choice "InstallType" "$t"
			echo "${types[$t]} $t"
			return
		fi
	done
}

get_numbers () {
	local nCtl nCmp nCph nSwf nCnd nTtl xName
	read nCtl nCmp nCph nSwf nCnd nTtl xName < <(get_type)

	echo "You have to have $nTtl boxen minimum for '$xName':"

	explain Controller	$nCtl
	explain Compute		$nCmp
	explain Ceph		$nCph
	explain Swift		$nSwf
	explain Cinder		$nCnd
}

get_numbers

echo ''>&2
echo "You have choosen:">&2
echo '===================='>&2
cat "$choice" >&2
echo '===================='>&2

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
