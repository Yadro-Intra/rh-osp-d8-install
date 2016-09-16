#!/bin/bash
echo 'Chapter 6. Configuring Advanced Customizations for the Overcloud'>&2
echo '6.13. Customizing Configuration on First Boot'>&2
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

[ -d "$tplDir/." ] || { mkdir -p "$tplDir" || error $? "Cannot mkdir '$tplDir'."; }
[ -d "$tplDir/." ] || error 1 "No dir '$tplDir'."

nsYaml="$tplDir/nameserver.yaml"
firstBootYaml="$tplDir/firstboot.yaml"

if [ ! -f "$nsYaml" ] || confirm "Replace '$nsYaml'? "; then
	declare -i i=0
	declare -a nsList=()
	while read ns ip tail; do
		echo "[$ns] [$ip] [$tail]">/dev/tty
		i=${#nsList[*]}
		nsList[$i]=$ip
	done < <(grep '^nameserver\>' < /etc/resolv.conf)
	echo "I'll add these NSes to all the nodes:">/dev/tty
	i=0
	for ip in ${nsList[*]}; do
		let i+=1
		printf '%3d: %s\n' $i $ip
	done >/dev/tty
	while read -p 'Type IP of extra NS to add or blank to continue: ' ip; do
		[ -z "$ip" ] && break
		i=${#nsList[*]}
		nsList[$i]=$ip
	done
	echo "So, I'll add these NSes to all the nodes:">/dev/tty
	i=0
	for ip in ${nsList[*]}; do
		let i+=1
		printf '%3d: %s\n' $i $ip
	done >/dev/tty
	confirm "Are you sure to continue? " || error 0 "Aborted."

	{	echo "heat_template_version: 2014-10-16"
		echo ""
		echo "description: >"
		echo "  Extra hostname configuration"
		echo ""
		echo "resources:"
		echo "  userdata:"
		echo "    type: OS::Heat::MultipartMime"
		echo "    properties:"
		echo "      parts:"
		echo "      - config: {get_resource: nameserver_config}"
		echo ""
		echo "  nameserver_config:"
		echo "    type: OS::Heat::SoftwareConfig"
		echo "    properties:"
		echo "      config: |"
		echo "        #!/bin/bash"
		for ip in ${nsList[*]}; do
			echo "        echo "nameserver $ip" >> /etc/resolv.conf"
		done
		echo ""
		echo "outputs:"
		echo "  OS::stack_id:"
		echo "    value: {get_resource: userdata}"
	} > "$nsYaml"
	edit "$nsYaml"
fi

if [ ! -f "$nsYaml" ] && [ -f "$firtBootYaml" ] && grep -q "$nsYaml" < "$firtBootYaml"; then
	rm -f "$firtBootYaml"
	error 1 "Your '$firtBootYaml' refers to inexisting file and was removed."
fi

if [ ! -f "$firstBootYaml" ] || confirm "Replace '$firstBootYaml'? "; then
	{	echo "resource_registry:"
		echo "  OS::TripleO::NodeUserData: $nsYaml"
	} > "$firstBootYaml"
	edit "$firstBootYaml"
fi

keep_env "$firstBootYaml"

confirm 'Do you want to START OVERCLOUD DEPLOYMENT RIGHT NOW to apply first boot change? ' \
	|| { echo "Ok.">/dev/tty; exit 0; }

run openstack overcloud deploy --templates -e "$firstBootYaml"

echo ''>&2
echo 'Done.'>&2
echo ''>&2
# EOF #
