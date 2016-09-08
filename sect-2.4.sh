#!/bin/bash
echo 'Chapter 2. Requirements'>&2
echo '2.4. Overcloud Requirements'>&2
echo ''>&2

error () {
	local -i rc=$1
	shift
	echo "ERROR($rc): $@">&2
	exit $rc
}

warn () {
	echo "WARNING: $@">&2
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

fold -s >&2 <<EOT
Booting an overcloud node from the SAN (FC-AL, FCoE, iSCSI) is not yet supported.

2.4.1. Compute Node Requirements

    64-bit x86 processor with support for the Intel 64 or AMD64 CPU extensions, and the AMD-V or Intel VT hardware virtualization extensions enabled. It is recommended this processor has a minimum of 4 cores. 

    A minimum of 6 GB of RAM.
    Add additional RAM to this requirement based on the amount of memory that you intend to make available to virtual machine instances. 

    A minimum of 40 GB of available disk space. 

    A minimum of one 1 Gbps Network Interface Cards, although it is recommended to use at least two NICs in a production environment. Use additional network interface cards for bonded interfaces or to delegate tagged VLAN traffic. 

    Each Compute node requires IPMI functionality on the server's motherboard. 

⁠2.4.2. Controller Node Requirements

    64-bit x86 processor with support for the Intel 64 or AMD64 CPU extensions. 

    A minimum of 32 GB of RAM for each Controller node. For optimal performance, it is recommended to use 64 GB for each Controller node.

    Important
    The amount of recommended memory depends on the number of CPU cores. A greater number of CPU cores requires more memory. For more information on measuring memory requirements, see "Red Hat OpenStack Platform Hardware Requirements for Highly Available Controllers" on the Red Hat Customer Portal. 

    A minimum of 40 GB of available disk space. 

    A minimum of 2 x 1 Gbps Network Interface Cards. Use additional network interface cards for bonded interfaces or to delegate tagged VLAN traffic. 

    Each Controller node requires IPMI functionality on the server's motherboard. 

⁠2.4.3. Ceph Storage Node Requirements

    64-bit x86 processor with support for the Intel 64 or AMD64 CPU extensions. 

    Memory requirements depend on the amount of storage space. Ideally, use at minimum 1 GB of memory per 1 TB of hard disk space. 

    Storage requirements depends on the amount of memory. Ideally, use at minimum 1 GB of memory per 1 TB of hard disk space. 

    The recommended Red Hat Ceph Storage node configuration requires a disk layout similar to the following:

        /dev/sda - The root disk. The director copies the main Overcloud image to the disk.
        /dev/sdb - The journal disk. This disk divides into partitions for Ceph OSD journals. For example, /dev/sdb1, /dev/sdb2, /dev/sdb3, and onward. The journal disk is usually a solid state drive (SSD) to aid with system performance.
        /dev/sdc and onward - The OSD disks. Use as many disks as necessary for your storage requirements. 

    A minimum of one 1 Gbps Network Interface Cards, although it is recommended to use at least two NICs in a production environment. Use additional network interface cards for bonded interfaces or to delegate tagged VLAN traffic. It is recommended to use a 10 Gbps interface for storage node, especially if creating an OpenStack Platform environment that serves a high volume of traffic. 

    Each Ceph node requires IPMI functionality on the server's motherboard. 

The director does not create partitions on the journal disk. You must manually create these journal partitions before the Director can deploy the Ceph Storage nodes.

The Ceph Storage OSDs and journals partitions require GPT disk labels, which you also configure prior to customization. For example, use the following command on the potential Ceph Storage host to create a GPT disk label for a disk or partition:

# parted [device] mklabel gpt

EOT

echo "Checking resources for 2.4.2. Controller Node Requirements...">&2

ncpucores=$(lscpu -axp=CORE | grep -v '^#' | wc -l)
(( ncpucores < 8 )) && warn "Too few CPU cores: $ncpucores. I need 8."

if lscpu | grep -w 'x86_64'; then
	:
elif lscpu | grep -w 'amd64'; then
	:
else
	error 1 "CPU must be either x86_64 or amd64. No way."
fi
lscpu | grep -w '64-bit' || error 1 "CPU cannot run 64-bit code. No way."

ram_gb=$(free -g | grep '^Mem:' | tr -s '[ \t]' '\t' | cut -f2)
(( ram_gb < 32 )) && error 1 "You must have at least 16G and not ${ram_gb}G. No way."
(( ram_gb < 64 )) && warn "You have to consider upgrade to 64G RAM from this ${ram_gb}G." \
		  || echo "RAM ${ram_gb}G looks ok.">&2
while read disk size_k; do
	size_g=$(( size_k >> 20 ))
	if (( size_g < 40 )); then
		warn "Size of '$disk' is ${size_g}GB (<40GB) which is BAD!"
	else
		echo "Size of '$disk' is ${size_g}GB which is good...">&2
	fi
done < <(df -lk | grep -v '/boot' | grep '^/dev/' | tr -s '[ \t]' '\t' | cut -f1,4)

n=0
while read intf; do
	let n+=1
	echo "Interface #$n: $intf">&2
done < <(ip -o link | grep -wv LOOPBACK | grep -w 'state UP' | cut -d: -f2)
(( n < 2 )) && error 1 "Too few network interfaces: $n (I want 2). No way."
echo "There are $n network interfaces, good..."

dmidecode | grep -qw IPMI || error 1 "This box must have IPMI. No way."
echo "IPMI is somehow supported here, good...">&2

echo ''>&2
echo 'You may continue.'>&2
echo ''>&2
# EOF #
