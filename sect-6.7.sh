#!/bin/bash
echo 'Chapter 6. Configuring Advanced Customizations for the Overcloud'>&2
echo '6.7. Configuring NFS Storage'>&2
echo ''>&2

hotDir='/usr/share/openstack-tripleo-heat-templates'
envDir="$hotDir/environments"
storageEnv="$envDir/storage-environment.yaml"

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

_yaml_has_param () {
	local file="$1"
	local name="$2"

	grep -q '^[[:space:]]\+'"$name"':' "$file"
}

_yaml_has_commented_param () {
	local file="$1"
	local name="$2"

	grep -q '^[[:space:]]*#[[:space:]]*'"$name"':' "$file"
}

_yaml_uncomment_param () {
	local file="$1"
	local name="$2"

	echo "+ Uncommenting '$name'...">/dev/tty
	sed -e '/^\s*#\s*'"$name"':/s/^\(\s*\)#\s*\('"$name"':\)/\1\2/' \
		-i "$file"
}

_yaml_set_param () {
	local file="$1" ; shift
	local name="$1" ; shift
	local value="$@"

	echo "+ Setting '$name' to '$value'...">/dev/tty
	sed -e '/^\s\+'"$name"':/s/^\(\s\+'"$name"':\s*\).*$/\1'"${value////\\/}"'/' \
		-i "$file"
}

_yaml_add_param () {
	local file="$1" ; shift
	local name="$1" ; shift
	local value="$@"

	echo "+ Adding '$name' with '$value'...">/dev/tty
	sed -e '1i\#FIXME# '"$name: $value" -i "$file"
}

yaml_set_param () {
	local file="$1" ; shift
	local name="$1" ; shift
	local value="$@"
	_yaml_has_param "$file" "$name" || {
		_yaml_has_commented_param "$file" "$name" \
			&& _yaml_uncomment_param "$file" "$name"
	}
	_yaml_has_param "$file" "$name" \
		&& _yaml_set_param "$file" "$name" "$@" \
		|| _yaml_add_param "$file" "$name" "$@"
}

pause () {
	local rep=''
	local prompt='Press <RETURN> to continue...'
	[ -n "$1" ] && prompt="$@"
	read -p "$prompt" rep
}

ask () {
	local value="$1" ; shift
	local prompt="$@"
	local rep=''
	read -p "$prompt [$value]: " rep
	[ -z "$rep" ] && echo "$value" || echo "$rep"
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)

tplDir="$home/templates"

[ -d "$hotDir/." ] || error 1 "No dir '$hotDir'."
[ -d "$envDir/." ] || error 1 "No dir '$envDir'."
[ -f "$storageEnv" ] || error 1 "No file '$storageEnv'."

[ -d "$tplDir/." ] || { mkdir -p "$tplDir" || error $? "Cannot mkdir '$tplDir'."; }
[ -d "$tplDir/." ] || error 1 "No dir '$tplDir'."

myStor="$tplDir/$(basename "$storageEnv")"

run cp -v "$storageEnv" "$myStor"

[ -f "$myStor" ] || error 1 "No file '$myStor'."

NFS_IP=192.0.2.230 # where to grab it from?????
NFS_IP=$(ask "$NFS_IP" 'Enter IP of your NFS server')

GLANCE_SEL_CTX='context=system_u:object_r:glance_var_lib_t:s0' # do not touch!

echo "Editing '$myStor':">/dev/tty
yaml_set_param "$myStor" CinderEnableIscsiBackend false
yaml_set_param "$myStor" CinderEnableRbdBackend false
yaml_set_param "$myStor" CinderEnableNfsBackend true
yaml_set_param "$myStor" NovaEnableRbdBackend false
yaml_set_param "$myStor" GlanceBackend "'file'"
yaml_set_param "$myStor" CinderNfsMountOptions "'rw,sync'"
yaml_set_param "$myStor" CinderNfsServers "'$NFS_IP:/cinder'"
yaml_set_param "$myStor" GlanceFilePcmkManage true
yaml_set_param "$myStor" GlanceFilePcmkFstype "'nfs'"
yaml_set_param "$myStor" GlanceFilePcmkDevice "'$NFS_IP:/glance'"
yaml_set_param "$myStor" GlanceFilePcmkOptions "'rw,sync,$GLANCE_SEL_CTX'"
echo "Done editing '$myStor'.">/dev/tty

echo "You have to inpect '$myStor' file now!">/dev/tty
pause
vi "$myStor"

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
