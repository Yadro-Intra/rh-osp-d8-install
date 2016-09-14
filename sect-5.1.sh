#!/bin/bash

echo "5.1. Registering Nodes for the Overcloud">&2
echo >&2

IPMI_BUS=lanplus	# use this way to speak IPMI
PXE_PACKETS=4		# wait for that many PXE (DHCP/BOOTP DISCOVER) packets

scriptDir=$(realpath $(dirname $0))

error () {
	local -i rc=$1
	shift
	echo "ERROR($rc): $@">/dev/tty
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

list_hmc_hosts () {
	grep -v '^#' < /etc/hosts | grep -wo 'node[0-9]\+hmc'
}

hmc_ip () {
	local hmc="$1"
	grep -wm1 "$hmc" < /etc/hosts | tr -s '[ \t]' '\t' | cut -f1
}

hmc_user () {
	local hmc="$1"
	grep -m1 "^machine[[:space:]]\\+$hmc[[:space:]]\\+login" < ~/.netrc \
	| tr -s '[ \t]' '\t' | cut -f4
}

hmc_pasw () {
	local hmc="$1"
	grep -m1 "^machine[[:space:]]\\+$hmc[[:space:]]\\+login" < ~/.netrc \
	| tr -s '[ \t]' '\t' | cut -f6
}

_ipmi_error () {
	local rc=$1 ; shift
	local cx=$1 ; shift
	[ "$cx" = 'fru' ] && return
	(( rc == 0 )) || error $rc "$@"
}

_ipmi () {
	local h="$1" ; shift
	local u=$(hmc_user "$h")
	local p=$(hmc_pasw "$h")
	ipmitool -H "$h" -U "$u" -P "$p" -I "$IPMI_BUS" "$@"
}

ipmi_query () {
	local h="$1" ; shift
	_ipmi "$h" "$@" || _ipmi_error $? $1 "Node '$h' misconfigured ($@)."
}

ipmi_power_cycle () {
	local h="$1" ; shift
	_ipmi "$h" chassis power cycle && return
	_ipmi "$h" chassis power on && return
	error $? "Node '$h' misconfigured ($@)."
}

ipmi_power_off () {
	_ipmi "$1" chassis power off || true
}

ipmi_lan_query () {
	ipmi_query "$1" lan print
}

ipmi_mc_query () {
	ipmi_query "$1" mc info
}

ipmi_power_query () {
	ipmi_query "$1" chassis power status
}

ipmi_fru_query () {
	ipmi_query "$1" fru print
}

ipmi_boot_query () {
	ipmi_query "$1" chassis bootparam get 5
}

ipmi_review () {
	local h='' a='' u='' p=''

	[ -x $(type -p ipmitool) ] || error 1 "No 'ipmitool' binary."

	echo "** Checking nodes' HMC accessibility:">/dev/tty
	for h in $(list_hmc_hosts); do
		a=$(hmc_ip "$h")
		u=$(hmc_user "$h")
		p=$(hmc_pasw "$h")
		echo "=====[ $h as $a ]====="
		ipmi_power_query "$h"
		ipmi_mc_query "$h" | grep '^IPMI'
		ipmi_lan_query "$h" | grep -E '^(IP|MAC)'
		ipmi_boot_query "$h" | grep -v '^Boot'
		ipmi_fru_query "$h" | grep -wiE 'memory size|cpu'
	done
}

build_json () {
	local node
	local -i cnt=0

	echo '{'
	echo -e '\t"nodes":['
	for node in $(list_hmc_hosts); do
		(( cnt > 0 )) && echo -e '\t\t},'
		let cnt+=1
		local nip=$(hmc_ip "$node")
		local nus=$(hmc_user "$node")
		local npw=$(hmc_pasw "$node")
		echo -e '\t\t{\t"__comment__":{"name":"'$node'"},'
		echo -e '\t\t\t"mac":[ "in:se:rt:ma:ch:er" ],'
	#	echo -e '\t\t\t"cpu":"1",'
	#	echo -e '\t\t\t"memory":"4096",'
	#	echo -e '\t\t\t"disk":"10",'
		echo -e '\t\t\t"arch":"x86_64",'
		echo -e '\t\t\t"pm_type":"pxe_ipmitool",'
		echo -e '\t\t\t"pm_user":"'$nus'",'
		echo -e '\t\t\t"pm_password":"'$npw'",'
		echo -e '\t\t\t"pm_addr":"'$nip'"'
	done
	echo -e '\t\t}'
	echo -e '\t]'
	echo '}'
	echo "nodes added: $cnt" >&2
}

create_json () {
	local json=instackenv.json ; [ -n "$1" ] && json="$1"

	build_json >> "$json"
	[ -x "$(type -p json_verify)" ] && json_verify < "$json"
	echo '...and you MUST edit "mac" entries to reflect your setup!'>/dev/tty
	read -p 'Press <RETURN> to edit...' </dev/tty
	vi "$json"
	[ -x "$(type -p json_verify)" ] && json_verify < "$json"
	echo "You may use your '$json' file now.">/dev/tty
}

check_hmc_specs () {
	grep -qw 'node[0-9]\+hmc' /etc/hosts \
		|| error 1 "Please list your HMC addresses of yor nodes" \
				"in the /etc/hosts as 'node99hmc' entries."
	grep -q '^machine[[:space:]]\+node[0-9]\+hmc' ~/.netrc \
		|| error 1 "Please list your HMC credentials" \
				"in your ~/.netrc as 'node99hmc' entries."
}

list_intf_up () {
	ip -o link | grep -w 'state UP' | cut -d: -f2
}

select_internal_intf () {
	local intf=''

	echo >/dev/tty
	echo "Select INTERNAL interface here:" >/dev/tty
	select intf in $(list_intf_up); do
		[ -n "$intf" ] && { echo "$intf"; return; }
	done </dev/tty
}

sniff_the_net () {
	local intf='' r=''

	[ -f "$scriptDir/recvRawEth.c" ] || error 1 "No file '$scriptDir/recvRawEth.c'."
	CFLAGS=-Wall make -C "$scriptDir" recvRawEth \
		|| error $? "Cannot make '$scriptDir/recvRawEth'."
	[ -f "$scriptDir/recvRawEth" ] || error 1 "No file '$scriptDir/recvRawEth'."
	[ -x "$scriptDir/recvRawEth" ] || error 1 "Not an executable '$scriptDir/recvRawEth'."

	clear
	intf=$(select_internal_intf)
	clear
	cat >/dev/tty <<-EOT

	It's time for some black magic now...

	Ok.
	You've already configured all your nodes to boot into PXE, haven't you?

	They are:
	$(list_hmc_hosts | sed -e '1,$s/^/\t* /')

	I'll try to make'em to boot PXE next time.
	I'll reboot (power cycle) the nodes for you and they supposed to run PXE.
	You have to watch the output of my sniffer and write down the MACs shown.

	It'd be good if every node will show up only one MAC.
	If not, you may face some troubles...

	I'll wait for $PXE_PACKETS PXE packets.
	You can either edit this ($0) script or type ^\\ (SIGQUIT) to stop waiting.

	NOTE!
	: It's not too fast to get to PXE!
	: For instance, an IBM x240 blade takes about 5 minutes to show its MAC.
	: I'd recommend you to open consoles on your nodes to see the progress...


EOT
	while :; do
		read -p "Do you want to perform this step (Y) or omit it (N): " r </dev/tty
		case "$r" in
		Y*|y*)	break;;
		N*|n*)	echo "Ok.">/dev/tty; return;;
		*)	echo "Yes or No?">/dev/tty;;
		esac
	done
	for node in $(list_hmc_hosts); do
		clear
		echo
		echo "Performing PXE of node '$node' listening on '$intf'."
		echo "Don't forget to quit the sniffer with ^\\ when boot attempt passed!"
		read -p 'Press <RETURN> to continue: ' </dev/tty
		_ipmi "$node" chassis bootdev pxe || error $? "Cannot set '$node' to PXE boot."
		ipmi_power_cycle "$node"
		sudo -E "$scriptDir/recvRawEth" -c$PXE_PACKETS -pI "$intf"
		ipmi_power_off "$node"
	done >/dev/tty
	echo "Well, I hope you've gathered all the info needed to proceed...">/dev/tty
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

[ -n "$1" -a -f "$1" ] && json=$(realpath "$1")

cd ~stack || error $? "No home?"
home=$(pwd)

[ -z "$1" ] && error 1 "Use: $(basename $0) <JSON-file> | 'create'"

check_hmc_specs
if [ "$1" = 'create' ]; then
	clear
	cat >/dev/tty <<-EOT
	I'll show you your nodes.

	$(list_hmc_hosts | sed -e '1,$s/^/\t* /')

	Please, make sure they are in "BIOS PC" or "legacy" boot mode!
	Plus, it's a good time to count RAM and CPUs installed...

	They are MUST be accessible via IPMI '$IPMI_BUS' protocol.
	If not, type ^C now and edit this ($0) script!

EOT
	read -p 'Press <RETURN> to continue: ' </dev/tty
	ipmi_review | less
	read -p 'Press <RETURN> to continue: ' </dev/tty
	clear
	sniff_the_net
	read -p 'Press <RETURN> to continue: ' </dev/tty
	clear
	create_json "$2"
	exit $?
fi

[ -z "$json" ] && json="$1"
[ -f "$json" ] || error 1 "No '$json' file."

if [ -x "$(type -p json_verify)" ]; then
	json_verify < "$json" || error 1 "File '$json' is not valid."
fi

run openstack baremetal instackenv validate -f "$json"
run openstack baremetal import --json "$json"
run openstack baremetal configure boot

ironic node-list

echo "You're done." >&2
echo >&2

# EOF #
