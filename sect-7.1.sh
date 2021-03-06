#!/bin/bash
echo 'Chapter 7. Creating the Overcloud'>&2
echo '7.1. Setting Overcloud Parameters'>&2
echo ''>&2

SCRIPT=`pwd`'/overcloud-deploy.sh'

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

echo ''>&2
[ -x "$SCRIPT" ] || error 1 "No executable '$SCRIPT'."
"$SCRIPT" --dry-run
echo "Done. Use '$SCRIPT' to deploy overcloud.">/dev/tty
echo ''>&2
# EOF #
