#!/usr/bin/env sh
set -e

# Docker install part of the script is highly inspired by https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script.
# Download link of original docker script: https://get.docker.com


##
# Variables
##

# Version
version='v0.15.2'

# Colors
green='\e[32m'
blue='\e[34m'
red='\e[31m'
dim='\e[2m'
undim='\e[22m'
clear='\e[0m'

# Unicode Symbols
checkmark='\u2713'
x_symbol='\u2716'

# Bar
separator='##############################################################'

# The channel to install from:
#   * nightly
#   * test
#   * stable
#   * edge (deprecated)
CHANNEL="stable"
DOWNLOAD_URL="https://download.docker.com"
REPO_FILE="docker-ce.repo"

sh_c='sh -c'

##
# Color Functions
##
Green(){
	echo -ne $green$1$clear
}

Blue(){
	echo -ne $blue$1$clear
}

Red(){
	echo -ne $red$1$clear
}

Dim(){
	echo -ne $dim$1$clear
}

##
# Functions
##

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

get_distribution() {
	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	# Returning an empty string here should be alright since the
	# case statements don't act unless you provide an actual value
	echo "$lsb_dist"
}

# add_debian_backport_repo adds the necessary debian backport to source list if not already in it.
# Some package installs may fail otherwise.
add_debian_backport_repo() {
	debian_version="$1"
	backports="deb http://ftp.debian.org/debian $debian_version-backports main"
	if ! grep -Fxq "$backports" /etc/apt/sources.list; then
		(set -x; $sh_c "echo \"$backports\" >> /etc/apt/sources.list")
	fi
}

# check_forked checks if this is a forked Linux distro for example Kali is forked from Debian.
check_forked() {

	# Check for lsb_release command existence, it usually exists in forked distros
	if command_exists lsb_release; then
		# Check if the `-u` option is supported
		set +e
		lsb_release -a -u > /dev/null 2>&1
		lsb_release_exit_code=$?
		set -e

		# Check if the command has exited successfully, it means we're in a forked distro
		if [ "$lsb_release_exit_code" = "0" ]; then
			# Get the upstream release info
			lsb_dist=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'id' | cut -d ':' -f 2 | tr -d '[:space:]')
			dist_version=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'codename' | cut -d ':' -f 2 | tr -d '[:space:]')
		else
			if [ -r /etc/debian_version ] && [ "$lsb_dist" != "ubuntu" ] && [ "$lsb_dist" != "raspbian" ]; then
				if [ "$lsb_dist" = "osmc" ]; then
					# OSMC runs Raspbian
					lsb_dist=raspbian
				else
					# We're Debian and don't even know it!
					lsb_dist=debian
				fi
				dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
				case "$dist_version" in
					10)
						dist_version="buster"
					;;
					9)
						dist_version="stretch"
					;;
					8|'Kali Linux 2')
						dist_version="jessie"
					;;
				esac
			fi
		fi
	fi
}

install_docker() {
	# perform some very rudimentary platform detection
	echo "> Bereite Docker Installation vor..."
	echo "> Versuche Platform zu erkennen..."
	lsb_dist=$( get_distribution )
	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

	if is_wsl; then
		echo
		echo ">   WSL ERKANNT: Es wird empfohlen Docker-Desktop für Windows zu verwenden"
		echo "     -> https://www.docker.com/products/docker-desktop"
		echo
		exit 1
	fi

	case "$lsb_dist" in

		ubuntu)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
		;;

		debian|raspbian)
			dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
			case "$dist_version" in
				10)
					dist_version="buster"
				;;
				9)
					dist_version="stretch"
				;;
				8)
					dist_version="jessie"
				;;
			esac
		;;

		centos|rhel)
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --release | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

	esac

	# Check if this is a forked Linux distro
	check_forked

	# Run setup for each distro accordingly
	case "$lsb_dist" in
		ubuntu|debian|raspbian)
			echo ">   $lsb_dist erkannt..."
			pre_reqs="apt-transport-https ca-certificates curl"
			if [ "$lsb_dist" = "debian" ]; then
				# libseccomp2 does not exist for debian jessie main repos for aarch64
				if [ "$(uname -m)" = "aarch64" ] && [ "$dist_version" = "jessie" ]; then
					echo ">     Füge potenziell fehlende Debian-Backports hinzu..."
					add_debian_backport_repo "$dist_version"
				fi
			fi

			echo ">     Update apt package index und installiere nötige Pakete um HTTPS Repository benutzen zu können..."
			if ! command -v gpg > /dev/null; then
				pre_reqs="$pre_reqs gnupg"
			fi
			apt_repo="deb [arch=$(dpkg --print-architecture)] $DOWNLOAD_URL/linux/$lsb_dist $dist_version $CHANNEL"
			(
				$sh_c 'apt-get update -qq >/dev/null'
				$sh_c "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pre_reqs >/dev/null"
				$sh_c "curl -fsSL \"$DOWNLOAD_URL/linux/$lsb_dist/gpg\" | apt-key add -qq - >/dev/null"
				$sh_c "echo \"$apt_repo\" > /etc/apt/sources.list.d/docker.list"
				$sh_c 'apt-get update -qq >/dev/null'
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				# Will work for incomplete versions IE (17.12), but may not actually grab the "latest" if in the test channel
				pkg_pattern="$(echo "$VERSION" | sed "s/-ce-/~ce~.*/g" | sed "s/-/.*/g").*-0~$lsb_dist"
				search_command="apt-cache madison 'docker-ce' | grep '$pkg_pattern' | head -1 | awk '{\$1=\$1};1' | cut -d' ' -f 3"
				pkg_version="$($sh_c "$search_command")"
				echo ">     Suche in Repository nach Version '$VERSION'"
				if [ -z "$pkg_version" ]; then
					echo
					echo ">     FEHLER: '$VERSION' konnte nicht in den apt-cache madison Ergebnissen gefunden werden."
					echo
					exit 1
				fi
				search_command="apt-cache madison 'docker-ce-cli' | grep '$pkg_pattern' | head -1 | awk '{\$1=\$1};1' | cut -d' ' -f 3"
				# Don't insert an = for cli_pkg_version, we'll just include it later
				cli_pkg_version="$($sh_c "$search_command")"
				pkg_version="=$pkg_version"
			fi

			echo ">     Installiere Docker..."
			(
				if [ -n "$cli_pkg_version" ]; then
					$sh_c "apt-get install -y -qq --no-install-recommends docker-ce-cli=$cli_pkg_version >/dev/null"
				fi
				$sh_c "apt-get install -y -qq --no-install-recommends docker-ce$pkg_version >/dev/null"
			)
			exit 0
			;;
		centos|fedora|rhel)
			echo ">   $lsb_dist erkannt..."
			yum_repo="$DOWNLOAD_URL/linux/$lsb_dist/$REPO_FILE"
			if ! curl -Ifs "$yum_repo" > /dev/null; then
				echo ">     Fehler: Konnte nicht mit 'curl' die Repository-Datei $yum_repo holen. Existiert die Datei?"
				exit 1
			fi
			if [ "$lsb_dist" = "fedora" ]; then
				pkg_manager="dnf"
				config_manager="dnf config-manager"
				enable_channel_flag="--set-enabled"
				disable_channel_flag="--set-disabled"
				pre_reqs="dnf-plugins-core"
				pkg_suffix="fc$dist_version"
			else
				pkg_manager="yum"
				config_manager="yum-config-manager"
				enable_channel_flag="--enable"
				disable_channel_flag="--disable"
				pre_reqs="yum-utils"
				pkg_suffix="el"
			fi

			echo ">     Füge Docker-Stable Dnf-Repository hinzu..."
			(
				$sh_c "$pkg_manager install -y -q $pre_reqs"
				$sh_c "$config_manager --add-repo $yum_repo"

				if [ "$CHANNEL" != "stable" ]; then
					$sh_c "$config_manager $disable_channel_flag docker-ce-*"
					$sh_c "$config_manager $enable_channel_flag docker-ce-$CHANNEL"
				fi
				$sh_c "$pkg_manager makecache"
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				pkg_pattern="$(echo "$VERSION" | sed "s/-ce-/\\\\.ce.*/g" | sed "s/-/.*/g").*$pkg_suffix"
				search_command="$pkg_manager list --showduplicates 'docker-ce' | grep '$pkg_pattern' | tail -1 | awk '{print \$2}'"
				pkg_version="$($sh_c "$search_command")"
				echo ">     Suche in Repository nach Version '$VERSION'"
				if [ -z "$pkg_version" ]; then
					echo
					echo ">     FEHLER: '$VERSION' nicht in $pkg_manager Ergebnisliste gefunden."
					echo
					exit 1
				fi
				search_command="$pkg_manager list --showduplicates 'docker-ce-cli' | grep '$pkg_pattern' | tail -1 | awk '{print \$2}'"
				# It's okay for cli_pkg_version to be blank, since older versions don't support a cli package
				cli_pkg_version="$($sh_c "$search_command" | cut -d':' -f 2)"
				# Cut out the epoch and prefix with a '-'
				pkg_version="-$(echo "$pkg_version" | cut -d':' -f 2)"
			fi

			echo ">     Installiere Docker..."
			(
				# install the correct cli version first
				if [ -n "$cli_pkg_version" ]; then
					$sh_c "$pkg_manager install -y -q docker-ce-cli-$cli_pkg_version"
				fi
				$sh_c "$pkg_manager install -y -q docker-ce$pkg_version"
			)
			echo_docker_as_nonroot
			exit 0
			;;
		*)
			if [ -z "$lsb_dist" ]; then
				if is_darwin; then
					echo
					echo ">   FEHLER: Nicht unterstütztes Betriebssystem 'macOS'."
					echo "    Bitte installieren Sie Docker-Desktop für macOS -> https://www.docker.com/products/docker-desktop"
					echo
					exit 1
				fi
			fi
			echo
			echo ">   FEHLER: Nicht unterstützte Distribution '$lsb_dist'"
			echo
			exit 1
			;;
	esac
	exit 1
}

remove_all_postgres_containers() {
	echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Alle Postgres-Container löschen')
$(Dim $separator)

"

	echo -ne " $(Red 'WARNUNG')

   Sie sind im Begriff $(Red 'ALLE(!)') laufenden & gestoppten Postgres-Container endgültig zu entfernen!
   Als Postgres-Container gelten alle Container, welche basierend auf einem Postgres-Image gebaut wurden.

   Sollte Sie sich zuvor eine Liste dieser Container ansehen wollen, beenden Sie den Skript mit CTRL+C
   und führen Sie folgenden Befehl aus:

   $(Blue 'docker ps -a | grep 'postgres:*'')


"

	read -p "> Möchten Sie fortfahren (j/N)? " choice

	if [ -z "$choice" ]; then
    	choice="n"
	fi

	case $choice in
		"j"|"J"|"y"|"Y") ;;
		*) exit 0 ;;
    esac

	echo -ne "

   Dies ist $(Red 'die letzte Warnung!')
   Es werden ALLE(!) Postgres-Container gelöscht! Dieser Schritt kann nicht rückgängig gemacht werden und
   $(Red 'Datenverlust') ist eine mögliche Folge!


"

	read -p "> Möchten Sie trotzdem fortfahren (j/N)? " choice

	if [ -z "$choice" ]; then
    	choice="n"
	fi

	case $choice in
		"j"|"J"|"y"|"Y") ;;
		*) exit 0 ;;
    esac

	echo "> Entferne Container"
	echo

	docker ps -a | awk '{ print $1,$2 }' | grep 'postgres:*' | awk '{print $1 }' | xargs -I {} docker rm -f {}
}

remove_unused_postgres_images() {
	echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Ungenutzte Postgres-Images löschen')
$(Dim $separator)

"

	echo -ne " $(Red 'WARNUNG')

   Sie sind im Begriff $(Red 'alle ungenutzten') Postgres-Images endgültig zu entfernen!

   Sollte Sie sich zuvor eine Liste dieser Images ansehen wollen, beenden Sie den Skript mit CTRL+C
   und führen Sie folgenden Befehl aus:

   $(Blue 'docker images | grep 'postgres'')


"

	read -p "> Möchten Sie fortfahren (j/N)? " choice

	if [ -z "$choice" ]; then
    	choice="n"
	fi

	case $choice in
		"j"|"J"|"y"|"Y") ;;
		*) exit 0 ;;
    esac

	echo "> Entferne Images"
	echo

	docker rmi $(docker images | grep 'postgres')
}

create_postgres_containers() {
	echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Postgres-Container erstellen & starten')
$(Dim $separator)

"

	# Get currently highest port in use
	highest_port="$(docker ps -a --format '{{.Image}} {{.Ports}}' | grep 'postgres:*' | grep -oP '(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]):\K([0-9]+)' | sort -n | tail -n 1)"

	# If no port assigned yet or port lower than 1024 default to postgres default port - 5432. Else, increment port by one.
	if [[ "$highest_port" -eq 0 ]] || [[ "$highest_port" -le 1024 ]]; then
		highest_port=5432
	else
		highest_port=$(($highest_port + 1))
	fi

	# Anzahl, Port and Postgres Version
	read -p "> Anzahl Container (1):              " container_count
	read -p "> Start Port ($highest_port):                 " external_port
	read -p "> Postgres Version (latest):         " postgres_version

	if [ -z "$container_count" ]; then
    	container_count=1
	fi

	if [ -z "$external_port" ]; then
    	external_port=$highest_port
	fi

	if [ -z "$postgres_version" ]; then
    	postgres_version="latest"
	fi

	# Restart policy
	restart="always"
	echo
	echo -ne "> Neustart Verhalten:
   $(Green '1)') Immer (Standard)
   $(Green '2)') Nur bei Absturz/Fehler
   $(Green '3)') Immer, außer wenn explizit gestoppt
   $(Green '4)') Nie
   $(Blue '>') "
	read a
    case $a in
		2) restart="on-failure";;
		3) restart="unless-stopped";;
		4) restart="no";;
		*);;
    esac

	# Database name
	echo
	read -p "> Datenbank Name (leer=keine DB):    " db_name

	# Postgres user password
	read -s -p "> Postgres Passwort:              " admin_pwd
	if [ -z "$admin_pwd" ]; then
		echo "> $(Red 'Fehler:') Postgres Passwort darf nicht leer sein."
		exit 1
	fi

	echo
	echo

	# Create multiple containers
	ip=$(ip route get 1.1.1.1 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}')
	end_port=$((external_port + container_count - 1))

	for port in `seq $external_port $end_port`; do
		local name="postgres_$RANDOM"
		docker run --name $name --publish $port:5432 --restart=$restart -e POSTGRES_PASSWORD=$admin_pwd -d postgres:$postgres_version

		# Only create database if name was given. Skip on empty.
		if ! [ -z "$db_name" ]; then

			# Wait 90 seconds for container to start
			is_running=1
			while [[ $i -lt 90 ]]; do
				if [[ "$(docker exec $name pg_isready)" == *"accepting"* ]]; then
					is_running=0
					break
				fi
				sleep 1s
				i=$[$i+1]
			done

			# Check if container is running and create database if so.
			if [ "$is_running" -eq 0 ]; then
				docker exec -it "$name" psql -U postgres -c "CREATE DATABASE $db_name;"
			else
				echo "> $(Red 'Warnung:') Konnte Datenbank nicht anlegen, da Container nicht im erwarteten Zeitraum gestartet ist..."
			fi
		fi

		echo "> Postgres-Container gestartet auf $ip:$port..."
		echo
    	done
}

list_postgres_containers() {
		echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Postgres-Container auflisten')
$(Dim $separator)

"
	docker ps -a | head -n1
	docker ps -a | grep 'postgres:*'
}

postgres_containers_stats() {
	watch -n 0 "docker stats --no-stream | head -n1 && docker stats --no-stream | grep 'postgres:*'"
}

postgres_containers_logs() {
		echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Postgres-Container Logs')
$(Dim $separator)

"
	docker container ls | grep 'postgres:*'

	echo -ne "
Container-ID
"

	read -p "> " id

	if [ -z "$id" ]; then
		exit 1
	fi

	clear
	docker container logs -f "$id"
}

print_header() {
	echo -ne "
$(Dim $separator)
$(Dim '#')
$(Dim '#') $(Blue 'Easy-Postgres-Containers '$version'')
$(Dim '#')
$(Dim '#') $(Dim 'Webseite:') $(Blue 'https://github.com/nikoksr/docker-scripts')
$(Dim '#') $(Dim 'Lizenz:')   $(Blue 'https://github.com/nikoksr/docker-scripts/LICENSE')
$(Dim '#')
$(Dim $separator)"
}

# menu prints the general and interactive navigation menu.
menu(){
print_header

echo -ne "

$(Green '1)') Postgres-Container erstellen & starten
$(Green '2)') Postgres-Container auflisten
$(Green '3)') Postgres-Container Live Statistiken
$(Green '4)') Postgres-Container Logs
$(Green '5)') Alle Postgres-Container entfernen
$(Green '6)') Ungenutzte Postgres-Images entfernen
$(Red '0)') Exit

$(Blue '>') "
    read a
    case $a in
		1) create_postgres_containers;;
		2) list_postgres_containers;;
		3) postgres_containers_stats;;
		4) postgres_containers_logs;;
		5) remove_all_postgres_containers;;
		6) remove_unused_postgres_images;;
		0) exit 0;;
		*) echo -e $red"Warnung: Option existiert nicht."$clear; menu;;
    esac
}

is_user_root() {
	if [ "$EUID" != 0 ]; then
		return 1
	else
		return 0
	fi
}

is_user_in_docker_group() {
		if id -nG "$USER" | grep -qw "docker"; then
    		return 0
		fi

		return 1
}

are_permissions_sufficient() {
	# If docker is not installed user has to be root
	if ! command_exists docker ; then
		if is_user_root; then
			return 0
		else
			echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Docker Installation')
$(Dim $separator)

Docker ist enweder nicht installiert oder die Installation konnte nicht gefunden werden. Bitte starten
Sie den Skript als 'root' Benutzer, um die automatische Installation und Einrichtung von Docker zu starten.
"
			return 1
		fi
	fi

	# If docker is installed user has to be in docker group
	if ! is_user_in_docker_group && ! is_user_root; then
			echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Berechtigung')
$(Dim $separator)

Der aktuelle Benutzer muss entweder Mitglied der 'docker'-Gruppe sein oder dieser Skript
muss als 'root' Benutzer ausgeführt werden.
Um den aktuellen Benutzer zur Gruppe 'docker' hinzuzufügen, führen Sie folgenden Befehl aus:

  usermod -a -G docker $USER && newgrp docker

Beende Skript aufgrund von unzureichenden Berechtigungen.
"
		return 1
	else
		return 0
	fi
}

# entrypoint for the application.
entrypoint() {
	# Cancel on ctrl+c
	trap "exit" INT

	# Check if user permissions are sufficient
	if ! are_permissions_sufficient; then
		exit 1
	fi

	# Install docker if not already
	if ! command_exists docker ; then
		install_docker
	fi

	# Start options menu only when dependencies are statisfied
	clear
	menu
}

# Start the application.
entrypoint
