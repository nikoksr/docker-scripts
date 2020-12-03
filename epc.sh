#!/usr/bin/env bash

##
# Variables
##

# Version
version='v0.14.0'

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

function is_docker_installed {
	if ! [ -x "$(command -v docker)" ]; then
		return 1
	fi

	return 0
}

# install_docker installs docker, adds the user to docker group and enables the service
function install_docker {
	echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Docker Installation')
$(Dim $separator)

"

	echo "> Bereite Docker Installation vor..."
    echo "> Suche Paketmanager..."
    if [ -x "$(command -v pacman)" ]; then
        echo ">   pacman gefunden..."
		pacman -S --needed docker
    elif [ -x "$(command -v apt)" ] || [ -x "$(command -v apt-get)" ]; then
        echo ">   apt gefunden..."
		# Apt install command differs between debian and ubuntu
		os_pretty_name=$(( lsb_release -ds || cat /etc/*release || uname -om ) 2>/dev/null | head -n1)
		os_name='ubuntu'
		if [[ $os_pretty_name == *"Debian"* ]]; then
			os_name="debian"
		fi
		# Run the installer
		install_docker_apt "$os_name"
	elif [ -x "$(command -v dnf)" ]; then
        echo ">   dnf gefunden..."
		install_docker_dnf
	elif [ -x "$(command -v yum)" ]; then
        echo ">   yum gefunden..."
		install_docker_yum
    else
        echo ">   Warnung: Es konnte kein unterstützter Paketmanager gefunden werden - Docker-Installation möglicherweise unvollständig und das weitere Vorgehen könnte fehlschlagen."
        echo ">   Fahre fort..."
    fi

	if is_docker_installed; then
		echo "> Docker wurde erfolgreich installiert..."
	else
		echo "> Docker konnte nicht installiert oder gefunden werden..."
		exit 1
	fi

	# Enable docker to start on boot
	echo "> Aktiviere Docker-Service Autostart beim Boot..."
	systemctl enable docker
}

function install_docker_apt() {
	echo ">     Update apt package index und installiere nötige Pakete um HTTPS Repository benutzen zu können..."

	apt-get update
	apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common

	echo ">     Füge Docker's offiziellen GPG Key hinzu..."
	curl -fsSL "https://download.docker.com/linux/$1/gpg" | apt-key add -

	echo ">     Füge Docker-Stable Apt-Repository hinzu..."
	add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/$1 $(lsb_release -cs) stable"

	echo ">     Installiere Docker Engine..."
	apt-get update
	apt-get install docker-ce docker-ce-cli containerd.io
}

function install_docker_dnf() {
	echo ">     Füge Docker-Stable Dnf-Repository hinzu..."
	dnf -y install dnf-plugins-core
	dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

	echo ">     Bei Fedora 31 oder höher muss die 'backward compatibility für Cgroups' freigeschaltet werden."
	echo "       In dem Fall den folgenden Befehl ausführen und System neustarten: "
	echo '       sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"'
}

function install_docker_yum() {
	echo ">     Füge Docker-Stable Yum-Repository hinzu..."
	yum install -y yum-utils
	yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

	echo ">     Installiere Docker Engine..."
	yum install docker-ce docker-ce-cli containerd.io
}

function remove_all_postgres_containers() {
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

	docker ps -a | awk '{ print $1,$2 }' | grep 'postgres:*' | awk '{print $1 }' | xargs -I {} docker rm -f {}
}

function remove_unused_postgres_images() {
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

	docker rmi $(docker images | grep 'postgres')
}

function create_postgres_containers() {
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

function list_postgres_containers() {
		echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Postgres-Container auflisten')
$(Dim $separator)

"
	docker ps -a | head -n1
	docker ps -a | grep 'postgres:*'
}

function postgres_containers_stats() {
	watch -n 0 "docker stats --no-stream | head -n1 && docker stats --no-stream | grep 'postgres:*'"
}

function postgres_containers_logs() {
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

function print_header() {
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
function menu(){
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

function is_user_root {
	if [ "$EUID" -ne 0 ]; then
		return 1
	else
		return 0
	fi
}

function is_user_in_docker_group {
		if id -nG "$USER" | grep -qw "docker"; then
    		return 0
		fi

		return 1
}

function are_permissions_sufficient {
	# If docker is not installed user has to be root
	if ! is_docker_installed ; then
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
function entrypoint() {
	# Cancel on ctrl+c
	trap "exit" INT

	# Check if user permissions are sufficient
	if ! are_permissions_sufficient; then
		exit 1
	fi

	# Install docker if not already
	if ! is_docker_installed ; then
		install_docker
	fi

	# Start options menu only when dependencies are statisfied
	clear
	menu
}

# Start the application.
entrypoint
