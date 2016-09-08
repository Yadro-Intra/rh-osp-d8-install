#!/bin/bash
echo 'Chapter 2. Requirements'>&2
echo '2.2. Undercloud Requirements'>&2
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

has () {
	local name="$1"
	shift
	test "$@" || error $? "Test '$name' for '$@' has failed."
}

# [ -w /etc/passwd ] || error 1 "Run me as root!"

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
(( ram_gb < 16 )) && error 1 "You must have at least 16G and not ${ram_gb}G. No way."
echo "RAM ${ram_gb}G looks ok.">&2

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

release=/etc/os-release
has release-file -f "$release"
source "$release" || error $? "Cannot source '$release' file."
has release-id -n "$ID" -a "$ID" = 'rhel'
has release-ver -n "$VERSION_ID" -a "$VERSION_ID" = '7.2'
echo "OS found is '$ID' version '$VERSION_ID', good...">&2

echo ''>&2
echo 'You may continue'>&2
echo ''>&2
# EOF #
