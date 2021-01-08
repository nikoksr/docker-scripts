#!/usr/bin/env bash
set -e

# Docker install part of the script is highly inspired by https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script.
# Download link of original docker script: https://get.docker.com

##
# Variables
##

# Version
version='v0.20.0'

# Colors
green='\e[32m'
blue='\e[34m'
red='\e[31m'
dim='\e[2m'
undim='\e[22m'
no_color='\e[0m'

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

sh_c='bash -c'

##
# Color Functions
##
green() {
	echo "$green$1$no_color"
}

blue() {
	echo "$blue$1$no_color"
}

red() {
	echo "$red$1$no_color"
}

dim() {
	echo "$dim$1$no_color"
}

##
# Functions
##
is_wsl() {
	case "$(uname -r)" in
	*microsoft* ) true ;; # WSL 2
	*Microsoft* ) true ;; # WSL 1
	* ) false;;
	esac
}

is_darwin() {
	case "$(uname -s)" in
	*darwin* ) true ;;
	*Darwin* ) true ;;
	* ) false;;
	esac
}

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

is_docker_daemon_running() {
	if pgrep -f docker > /dev/null; then
		return 0
	fi
	return 1
}

start_docker_daemon() {
	if command_exists systemctl; then
		systemctl is-active --quiet docker.service || systemctl enable --now --quiet docker.service > /dev/null
	# elif command_exists service; then
	# 	service docker status > /dev/null || service docker start > /dev/null
	else
		pgrep -f docker > /dev/null || dockerd & > /dev/null
	fi
}

install_docker() {
		echo -ne "

$(dim $separator)
$(dim '# ')$(blue 'Docker Installation')
$(dim $separator)

"

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
				export APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=0
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
			;;
		arch|manjaro)
			echo ">   $lsb_dist erkannt..."
			echo ">     Installiere Docker..."
			(
				pacman -S --needed --noconfirm --quiet docker > /dev/null
			)
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

	# Verify installation
	if ! command_exists docker; then
		echo "> Docker konnte nicht installiert werden..."
		exit 1
	fi

	echo "> Docker wurde erfolgreich installiert..."
	exit 0
}

remove_all_postgres_containers() {
	echo -ne "

$(dim $separator)
$(dim '# ')$(blue 'Alle Postgres-Container löschen')
$(dim $separator)

"

	echo -ne " $(red 'WARNUNG')

   Sie sind im Begriff $(red 'ALLE(!)') laufenden & gestoppten Postgres-Container endgültig zu entfernen!
   Als Postgres-Container gelten alle Container, welche basierend auf einem Postgres-Image gebaut wurden.

   Sollte Sie sich zuvor eine Liste dieser Container ansehen wollen, beenden Sie den Skript mit CTRL+C
   und führen Sie folgenden Befehl aus:

   $(blue 'docker ps -a | grep 'postgres:*'')


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

   Dies ist $(red 'die letzte Warnung!')
   Es werden ALLE(!) Postgres-Container gelöscht! Dieser Schritt kann nicht rückgängig gemacht werden und
   $(red 'Datenverlust') ist eine mögliche Folge!


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

$(dim $separator)
$(dim '# ')$(blue 'Ungenutzte Postgres-Images löschen')
$(dim $separator)

"

	echo -ne " $(red 'WARNUNG')

   Sie sind im Begriff $(red 'alle ungenutzten') Postgres-Images endgültig zu entfernen!

   Sollte Sie sich zuvor eine Liste dieser Images ansehen wollen, beenden Sie den Skript mit CTRL+C
   und führen Sie folgenden Befehl aus:

   $(blue 'docker images | grep 'postgres'')


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
$(dim '# ')$(blue 'Postgres-Container erstellen & starten')
$(dim $separator)
$(dim "

Tipp: Drücken Sie 'Enter', um einen in Klammern stehenden
      Standardwert zu verwenden.")


$(blue "### Konfiguration")

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
	echo -ne "> Anzahl Container $(dim '(1)'):                          "
	read container_count
	if [ -z "$container_count" ]; then
    	container_count=1
	fi

	echo -ne "> Port $(dim '('$highest_port')'):                                   "
	read external_port
	if [ -z "$external_port" ]; then
    	external_port=$highest_port
	fi

	echo -ne "> Postgres Version $(dim '(latest)'):                     "
	read postgres_version
	if [ -z "$postgres_version" ]; then
    	postgres_version="latest"
	fi

	# Logging behaviour
	echo -ne "> Maximal Anzahl Log Dateien $(dim '(5)'):                "
	read max_log_file
	if [ -z "$max_log_file" ]; then
		max_log_file="5"
	fi

	echo -ne "> Maximale Größer einer Log-Datei $(dim '(20m)'):         "
	read max_log_file_size
	if [ -z "$max_log_file_size" ]; then
		max_log_file_size="20m"
	fi

	# Restart policy
	restart="always"
	echo
	echo -ne "> Neustart Verhalten:
   $(blue '1)') Immer $(dim '(Standard)')
   $(blue '2)') Nur bei Absturz/Fehler
   $(blue '3)') Immer, außer wenn explizit gestoppt
   $(blue '4)') Nie

   $(blue '>') "
	read choice
    case "$choice" in
		2) restart="on-failure";;
		3) restart="unless-stopped";;
		4) restart="no";;
		*) ;;
    esac
	echo

	# Postgres user password
	echo -ne "> Postgres Admin Passwort $(dim '(postgres)'):            "
	read -s admin_pwd
	echo
	if [ -z "$admin_pwd" ]; then
		admin_pwd="postgres"
	else
		echo -ne "> Passwort bestätigen:                           "
		read -s admin_pwd_confirm
		echo
		if [ ! "$admin_pwd" = "$admin_pwd_confirm" ]; then
			echo
			echo -e "> $(red 'FEHLER'): Eingegebene Passwörter unterscheiden sich"
			echo
			exit 1
		fi
	fi

	# Database name
	echo -ne "> Datenbank Name $(dim '(postgres)'):                     "
	read db_name
	if [ -z "$db_name" ]; then
		db_name="postgres"
	fi

	echo

	echo -ne "$(blue "### Postgres Image laden")\n\n"
	docker pull postgres:"$postgres_version"

	# Create multiple containers
	echo -ne "\n$(blue "### Container starten")\n\n"

	ip=$(ip route get 1.1.1.1 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}')
	end_port=$((external_port + container_count - 1))

	for port in `seq $external_port $end_port`; do
		local name="postgres_$RANDOM"
		docker run \
			--name "$name" \
			--log-opt max-file="$max_log_file" \
			--log-opt max-size="$max_log_file_size" \
			--publish "$port":5432 \
			--restart="$restart" \
			-e POSTGRES_PASSWORD="$admin_pwd" \
			-d \
			postgres:"$postgres_version" > /dev/null

		# Only create database if name was given. Skip on empty.
		if [ ! -z "$db_name" ] && [ ! "$db_name" = "postgres" ] ; then

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
				docker exec -it "$name" psql -U postgres -c "CREATE DATABASE $db_name;" && \
				echo "> Datenbank $db_name erfolgreich erstellt..."
			else
				echo "> $(red 'Warnung:') Konnte Datenbank nicht anlegen, da Container nicht im erwarteten Zeitraum gestartet ist..."
			fi
		fi

		echo -e "> Container gestartet auf $(green $ip:$port)..."
    	done
}

list_postgres_containers() {
		echo -ne "

$(dim $separator)
$(dim '# ')$(blue 'Postgres-Container auflisten')
$(dim $separator)

"
	docker ps | head -n1
	docker ps -a | grep 'postgres:*'
}

postgres_containers_stats() {
	watch -n 0 "docker stats --no-stream | head -n1 && docker stats --no-stream | grep 'postgres:*'"
}

postgres_containers_logs() {
		echo -ne "

$(dim $separator)
$(dim '# ')$(blue 'Postgres-Container Logs')
$(dim $separator)

"
	docker ps | head -n1
	docker container ls | grep 'postgres:*'

	echo
	echo -ne $(blue 'Container-ID eingeben')
	echo
	read -p "> " id

	if [ -z "$id" ]; then
		exit 1
	fi

	echo
	read -p "> Live verfolgen (j/N)? " choice

	if [ -z "$choice" ]; then
    	choice="n"
	fi

	clear
	case $choice in
		"j"|"J"|"y"|"Y") docker container logs --since 0s -f "$id";;
		*) docker container logs "$id";;
    esac
}

postgres_containers_top() {
		echo -ne "

$(dim $separator)
$(dim '# ')$(blue 'Postgres-Container Top')
$(dim $separator)

"
	docker ps | head -n1
	docker container ls | grep 'postgres:*'

	echo
	echo -ne "$(blue 'Container-ID eingeben')"
	echo
	read -p "> " id

	if [ -z "$id" ]; then
		exit 1
	fi

	clear
	watch -n 0 docker container top "$id"
}

print_header() {
	echo -ne "
$(dim $separator)
$(dim '#')
$(dim '#') $(blue 'Easy-Postgres-Containers '$version'')
$(dim '#')
$(dim '#') $(dim 'Webseite:') $(blue 'https://github.com/nikoksr/docker-scripts')
$(dim '#') $(dim 'Lizenz:')   $(blue 'https://github.com/nikoksr/docker-scripts/LICENSE')
$(dim '#')
$(dim $separator)"
}

# menu prints the general and interactive navigation menu.
menu(){
print_header

echo -ne "

$(green '1)') Postgres-Container erstellen & starten
$(green '2)') Postgres-Container auflisten
$(green '3)') Postgres-Container Statistiken
$(green '4)') Postgres-Container Log
$(green '5)') Postgres-Container Top
$(green '6)') Alle Postgres-Container entfernen
$(green '7)') Ungenutzte Postgres-Images entfernen
$(red '0)') Exit

$(blue '>') "
    read a
    case $a in
		1) clear;print_header;create_postgres_containers;;
		2) clear;print_header;list_postgres_containers;;
		3) clear;print_header;postgres_containers_stats;;
		4) clear;print_header;postgres_containers_logs;;
		5) clear;print_header;postgres_containers_top;;
		6) clear;print_header;remove_all_postgres_containers;;
		7) clear;print_header;remove_unused_postgres_images;;
		0) exit 0;;
		*) echo -e $red"Warnung: Option existiert nicht."$no_color; menu;;
    esac
}

is_user_root() {
	if [ "$EUID" -eq 0 ]; then
		return 0
	else
		return 1
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
		fi
		echo -ne "
$(dim $separator)
$(dim '# ')$(blue 'Docker Installation')
$(dim $separator)

Docker ist enweder nicht installiert oder die Installation konnte nicht gefunden werden. Bitte starten
Sie den Skript als 'root' Benutzer neu, um die automatische Installation und Einrichtung von Docker zu starten.
"
		return 1
	fi

	# If docker service is not running, need root to start and enable service
	if ! is_docker_daemon_running; then
		if is_user_root; then
			return 0
		fi
		echo -ne "
$(dim $separator)
$(dim '# ')$(blue 'Docker Installation')
$(dim $separator)

Docker-Daemon scheint nicht aktiviert zu sein. Bitte starten Sie den Skript als 'root' Benutzer neu, um die
automatische Aktivierung des Docker-Daemons zu starten.
"
	return 1
	fi

	# If docker is installed user has to be in docker group
	if ! is_user_in_docker_group && ! is_user_root; then
			echo -ne "
$(dim $separator)
$(dim '# ')$(blue 'Berechtigung')
$(dim $separator)

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
	if ! command_exists docker; then
		install_docker
	fi

	# Start docker daemon if not already running
	if ! is_docker_daemon_running; then
		start_docker_daemon
	fi

	# Start options menu only when dependencies are statisfied
	clear
	menu
}

# Start the application.
entrypoint
