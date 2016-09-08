#!/bin/bash
echo 'Chapter 2. Requirements'>&2
echo '2.5. Repository Requirements'>&2
echo ''>&2

declare -a repos=(
	'rhel-7-server-rpms'
	'rhel-7-server-extras-rpms'
	'rhel-7-server-rh-common-rpms'
	'rhel-7-server-satellite-tools-6.1-rpms'
	'rhel-ha-for-rhel-7-server-rpms'
	'rhel-7-server-openstack-8-director-rpms'
	'rhel-7-server-openstack-8-rpms'
	'rhel-7-server-rhceph-1.3-osd-rpms'
	'rhel-7-server-rhceph-1.3-mon-rpms'
)

rh_repo_conf=/etc/yum.repos.d/redhat.repo

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

[ -f "$rh_repo_conf" ] || error 1 "No RH repo config '$rh_repo_conf'."
W=0
for repo in ${repos[*]}; do
	grep "$repo" < "$rh_repo_conf" || { let W+=1; warn "No repo '$repo' configured."; }
done
(( W > 0 )) && error 1 "Not all mandatory repos configured."

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
