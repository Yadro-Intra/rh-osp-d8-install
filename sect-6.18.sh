#!/bin/bash
echo 'Chapter 6. Configuring Advanced Customizations for the Overcloud'>&2
echo '6.18. Using Customized Core Heat Templates'>&2
echo ''>&2

sysTplDir='/usr/share/openstack-tripleo-heat-templates'

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

confirm () {
        local rep=''
        local prompt='Press <RETURN> to continue...'
        [ -n "$1" ] && prompt="$@"
        while :; do
                read -p "$prompt" rep
                case "$rep" in
                y*|Y*) return 0;;
                n*|N*) return 1;;
                *) echo "Yes or No?">/dev/tty;;
                esac
        done
}

edit () {
        local e="$VISUAL"
        [ -z "$e" ] && e="$EDITOR"
        [ -z "$e" ] && e=vi
        "$e" "$@"
}

keep_env () {
        local env="$1"

        [ -f "$env" ] || error 1 "No env file '$env'."
        if ! grep -q "^$env"'$' "$home/overcloud-extra-env.list"; then
                echo "$env" >> "$home/overcloud-extra-env.list"
        fi
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error $? "No home?"
home=$(pwd)
tplDir="$home/templates"
sysTplCopy="$tplDir/my-overcloud"

echo ''>&2

[ -d "$sysTplDir/." ] || error 1 "No system template dir '$systplDir'."
[ -d "$sysTplCopy/." ] || { mkdir -p "$sysTplCopy" || error $? "Cannot mkdir '$sysTplCopy'."; }
hasFiles=no
for f in "$sysTplCopy"/*; do
	[ -d "$f" ] && { hasFiles=yes; break; }
	[ -f "$f" ] && { hasFiles=yes; break; }
done
if [ "$hasFiles" = 'yes' ]; then
	confirm "Are you sure to overwrite your copy? " || error 0 "Aborted."
fi
cp -rv "$sysTplDir"/* "$sysTplCopy/" || error $? "Cannot copy '$sysTplDir/' to '$sysTplCopy/'."

echo 'Done.'>&2
echo ''>&2
# EOF #
