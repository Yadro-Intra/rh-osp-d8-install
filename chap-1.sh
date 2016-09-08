#!/bin/bash

chapter=$(basename $0 .sh)
chapter=${chapter/chap-/}

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

section_list () {
	echo ./sect-"$1".*.sh | tr -s '[:space:]' '\012' | sort -n -t. -k3
}

echo "===========================================================" >&2
echo "Overview:" >&2
for script in $(section_list $chapter); do
	if [ -x "$script" ]; then
		head -n4 "$script" | grep -w '^echo' | $SHELL >&2
	elif [ -f "$script" ]; then
		echo "WARNING: script '$script' exists, but not executable.">&2
	else
		echo "ERROR: no script '$script' exists.">&2
	fi
done

echo "===========================================================" >&2
echo "Execution:" >&2
for script in $(section_list $chapter); do
	if [ -x "$script" ]; then
		head -n4 "$script" | grep -w '^echo' | $SHELL >&2

		if run env NOPAUSE=$NOPAUSE "$script"; then
			: echo "GOOD: script '$script' completed ok.">&2
		else
			echo "WARNING: script '$script' terminated with errors ($?).">&2
		fi
	elif [ -f "$script" ]; then
		echo "WARNING: script '$script' exists, but not executable.">&2
	else
		echo "ERROR: no script '$script' exists.">&2
	fi
done

{ echo ; echo "=== CHAPTER $chapter COMPLETE ==="; echo; } >&2

# EOF #
