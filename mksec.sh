#!/bin/bash

rtfm='https://access.redhat.com/documentation/en/red-hat-openstack-platform/8/single/director-installation-and-usage/'
ltfm='tfm.html'
itfm='tfm.idx'
chap='chapters.idx'
sect='sections.idx'

shell=/bin/bash

error () {
	local -i rc=$1
	shift
	echo "ERROR($rc): $@">&2
	exit $rc
}

has () {
	local name="$1"
	shift
	test "$@" || error $? "Test '$name' for '$@' failed."
}

has shell -f "$shell" -a -x "$shell"

curl=$(type -p curl)
has curl -n "$curl" -a -f "$curl" -a -x "$curl"

html2text () {
	# remove HTML tags
	# convert &nbsp; (U+00A0 aka '\x2c\xa0') to normal space '\x20'
	# replace stale word joiners (\xe2\x81\xa0) with space
	# drop leading spaces
	# &times; (\xc2\x97, \xc3\x97)-> '*'
	# '\xe2\x80\x9c' -> '"'
	# '\xe2\x80\x9d' -> '"'
	# '\xe2\x80\x99' -> "'"
	# '\xc2\xa9' -> '(C)'
	# collapse sequences of spaces and tabs to a single space
	# drop duplicate lines
	sed	-e '1,$s/<[^>]\+>/\n/g' \
		-e '1,$s/\xc2\xa0/ /g' \
		-e '1,$s/[[:space:]]\+\xe2\x81\xa0[[:space:]]\+/ /g' \
		-e '1,$s/^[[:space:]]\+//g' \
		-e '1,$s/\xc2\x97/*/g' \
		-e '1,$s/\xc3\x97/*/g' \
		-e '1,$s/\xe2\x80[\x9c\x9d]/"/g' \
		-e '1,$s/\xe2\x80\x99/'"'"'/g' \
		-e '1,$s/\xc2\xa9/(C)/g' \
	| tr -s '[ \t]' ' ' \
	| uniq
}

fetch_TFM_and_build_indicies () {
	# fetch and cache the TFM in HTML
	"$curl" -ko "$ltfm" "$rtfm" || error $? "Cannot fetch TFM."

	# adjust to plain text
	html2text < "$ltfm" > "$itfm"

	# build indices for chapters and sections
	grep '^Chapter[[:space:]]\+[0-9]\+\.[[:space:]]\+' < "$itfm" | uniq > "$chap"
	grep '^[0-9]\+[0-9.]\+\.[[:space:]]\+' < "$itfm" | uniq > "$sect"
}

chapter_title () {
	local chapter=$(cut -d. -f1 <<<"$1")
	grep -m1 "^Chapter $chapter\\. " < "$chap"
}

section_title () {
	local section="$1"
	grep -m1 "^${section//./\\.}\\. " < "$sect"
}

add () {
	# add a line to the script
	echo "$@" >> "$file"
}

if [ "$1" = 'cache' ]; then
	fetch_TFM_and_build_indicies
	echo "TFM cache and indicies have been rebuilt.">&2
	exit
fi

[ -z "$1" ] && error 1 "$(basename $0) <section-number>"

[ -f "$ltfm" ] || fetch_TFM_and_build_indicies

if [ "$1" = 'auto' ]; then
	for ch in $(grep -o '[0-9]\+\.' <"$chap" | sort -nu); do
		echo "Chapter '${ch%%.}'.">&2
		for se in $(grep -o '^'${ch%%.}'\.[0-9]\+\.' <"$sect" | sort -n -t. -k2 -u); do
			echo "Section '${se%%.}'.">&2
			file="sect-${se%%.}.sh"
			[ -f "$file" ] && continue
			[ -f "$file".template ] && continue
			echo "Writing '$file'..." >&2
			"$0" "${se%%.}"
			[ -f "$file" ] && mv -v "$file" "$file".template
		done
	done
	exit
fi

section="$1"
echo "/$section" | cut -d/ -f2- | grep -q '^[0-9]\+\.[0-9]\+$' \
	|| error 1 "Bad section number '$1'."

file="sect-${section}.sh"
[ -f "$file" ] && error 1 "Script '$file' for section '$section' already here."
[ -f "$file".template ] && { mv -v "$file".template "$file" || error $? "Cannot use teplate for '$file'."; exec vim "$file"; }

# create the script for section $section of the TFM

echo "#!$shell" > "$file" || error $? "Cannot create '$file'."

add "echo '$(chapter_title "$section")'>&2"
add "echo '$(section_title "$section")'>&2"
add "echo ''>&2"

cat >>"$file" <<EOT

error () {
	local -i rc=\$1
	shift
	echo "ERROR(\$rc): \$@">&2
	exit \$rc
}

run () {
	local r='' p="\$@"

	if [ "\$NOPAUSE" = 'yes' ]; then
		echo "Run [\$p] (no pause)">&2
	else
		read -p "Run [\$p] " r
		case "\$r" in
		c*|C*)	error 0 "Cancelled";;
		a*|A*)	error 0 "Aborted.";;
		n*|N*)	echo "Skipped.">&2; return 0;;
		y*|Y*)	;;
		esac
	fi
	"\$@"
}

confirm () {
        local rep=''
        local prompt='Press <RETURN> to continue...'
        [ -n "\$1" ] && prompt="\$@"
        while :; do
                read -p "\$prompt" rep
                case "\$rep" in
                y*|Y*) return 0;;
                n*|N*) return 1;;
                *) echo "Yes or No?">/dev/tty;;
                esac
        done
}

edit () {
        local e="\$VISUAL"
        [ -z "\$e" ] && e="\$EDITOR"
        [ -z "\$e" ] && e=vi
        "\$e" "\$@"
}

keep_env () {
        local env="\$1"

        [ -f "\$env" ] || error 1 "No env file '\$env'."
        if ! grep -q "^\$env"'\$' "\$home/overcloud-extra-env.list"; then
                echo "\$env" >> "\$home/overcloud-extra-env.list"
        fi
}

[ -w /etc/passwd ] && error 1 "Don't run me as root. User 'stack' instead."
[ "\$(id -nu)" = 'stack' ] || error 1 "Run me as user 'stack' please."

cd ~stack || error \$? "No home?"
home=\$(pwd)

EOT

add "echo ''>&2"
add "echo 'Done.'>&2"
add "echo ''>&2"
add '# EOF #'

chmod +x "$file" || error $? "Cannot chmod +x '$file'."

echo "Done." >&2

exec vim "$file"

# EOF #
