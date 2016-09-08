#!/bin/bash
echo '1.1. Undercloud'>&2
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

cat >&2 <<EOT
Undercloud means Director here.

Environment planning - The Undercloud provides planning functions for users to assign Red Hat OpenStack Platform roles, including Compute, Controller, and various storage roles.

Bare metal system control - The Undercloud uses the Intelligent Platform Management Interface (IPMI) of each node for power management control and a PXE-based service to discover hardware attributes and install OpenStack to each node. This provides a method to provision bare metal systems as OpenStack nodes.

Orchestration - The Undercloud provides and reads a set of YAML templates to create an OpenStack environment.

 The Undercloud consists of the following components:

  OpenStack:
    Bare Metal (ironic) and Compute (nova) - Manages bare metal nodes.
    Networking (neutron) and Open vSwitch - Controls networking for bare metal nodes.
    Image Service (glance) - Stores images that are written to bare metal machines.
    Orchestration (heat) and Puppet - Provides orchestration of nodes and configuration of nodes after the director writes the Overcloud image to disk.
    Telemetry (ceilometer) - Performs monitoring and data collection.
    Identity (keystone) - Provides authentication and authorization for the director's components.
  Plus
    MariaDB - The database back end for the director.
    RabbitMQ - Messaging queue for the director's components. 

Continue to 1.2.
EOT

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
