#!/usr/bin/env bash

##
# Variables
##

# Version
version='v0.8.0'

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

# check_docker_install checks if docker was installed correctly and installs it in case its missing.
function check_docker_install {
	echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Docker installieren')
$(Dim $separator)

"
	# Check if docker is already installed.
	if [ -x "$(command -v docker)" ]; then
		echo "> Docker ist bereits installiert..."
    else
		echo "> Bereite Docker Installation vor..."
    	echo "> Suche Paketmanager..."

    	if [ -x "$(command -v pacman)" ]; then
    	    echo ">   pacman gefunden..."
    	    sudo pacman -S --needed docker

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
    fi


	# Enable docker to start on boot
	echo "> Aktiviere Docker-Service Autostart beim Boot..."
	sudo systemctl enable docker

	# Add user to docker group if not already in it. This is at the beginning so that user will still
	# be automatically added to docker group even if docker is already installed.
	echo "> Checke Docker-Gruppe..."
	add_docker_group
}

function install_docker_apt() {
	echo ">     Update apt package index und installiere nötige Pakete um HTTPS Repository benutzen zu können..."

	sudo apt-get update
	sudo apt-get install \
    	apt-transport-https \
    	ca-certificates \
    	curl \
    	gnupg-agent \
    	software-properties-common

	echo ">     Füge Docker's offiziellen GPG Key hinzu..."
	curl -fsSL "https://download.docker.com/linux/$1/gpg" | sudo apt-key add -

	echo ">     Füge Docker-Stable Apt-Repository hinzu..."
	sudo add-apt-repository \
   		"deb [arch=amd64] https://download.docker.com/linux/$1 \
   		$(lsb_release -cs) \
   		stable"

	echo ">     Installiere Docker Engine..."
	sudo apt-get update
	sudo apt-get install docker-ce docker-ce-cli containerd.io
}

function install_docker_dnf() {
	echo ">     Füge Docker-Stable Dnf-Repository hinzu..."
	sudo dnf -y install dnf-plugins-core
	sudo dnf config-manager \
    	--add-repo \
    	https://download.docker.com/linux/fedora/docker-ce.repo

	echo ">     Bei Fedora 31 oder höher muss die 'backward compatibility für Cgroups' freigeschaltet werden."
	echo ">     In dem Fall den folgenden Befehl ausführen und System neustarten: "
	echo '>     sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"'
}

function install_docker_yum() {
	echo ">     Füge Docker-Stable Yum-Repository hinzu..."
	sudo yum install -y yum-utils
	sudo yum-config-manager \
    	--add-repo \
    	https://download.docker.com/linux/centos/docker-ce.repo

	echo ">     Installiere Docker Engine..."
	sudo yum install docker-ce docker-ce-cli containerd.io
}

function add_docker_group() {
	if is_user_in_group $USER docker; then
		return 0
	fi

	if ! grep -q -E "^docker:" /etc/group; then
		echo "> Erstelle Docker Gruppe..."
    	sudo groupadd docker
    fi

	echo "> Füge aktuellen Benutzer zur Gruppe hinzu..."
	sudo usermod -aG docker $USER
	echo "> $(Blue 'Hinweis:') Sie müssen sich nun einmalig ab- und wieder anmelden, um die neue Gruppenzugehörigkeit zu aktivieren."
	echo "  Die Zugehörigkeit in der Docker-Gruppe ermöglicht es Ihnen, Docker ohne 'root'-Rechte verwendet werden zu können."
}

function install_and_setup_sudo() {
	echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Sudo installieren')
$(Dim $separator)

"

	if [ -x "$(command -v sudo)" ]; then
		echo "> Sudo ist bereits installiert..."
		return 0
    fi

	echo -ne " $(Red 'WARNUNG')

   Zur Installation des 'sudo' Programm's wird der Skript versuchen sich als Benutzer root anzumelden.
   Der Benutzer root hat unter Linux uneingeschränkte(!) Nutzungsrechte, welche benötigt werden, um das
   Programm 'sudo' installieren und konfigurieren zu können.
   Für jegliche Fehler, Probleme oder ähnliches ungewolltes Fehlverhalten wird nicht gehaftet. Dies
   ist freie und offene Software, welche ohne jegliche Garantie und Gewährleistung kommt.
   Sollten Sie sich unsicher sein, lassen Sie das Programm 'sudo' von einem Systemadministrator o.Ä.
   Ihres Vertrauens installieren und führen Sie danach diesen Skript erneut aus.

"

	read -p "> Möchten Sie fortfahren (j/N)? " choice

	if [ -z "$choice" ]; then
    	choice="n"
	fi

	case $choice in
		"j"|"J"|"y"|"Y") ;;
		*) exit 0 ;;
    esac

	# Try to install sudo
	echo "> Melde Nutzer root an..."
	local og_user=$USER
	su -c "apt-get update && apt-get install sudo && if grep -Eiq '%sudo\s+ALL\s*=\s*\(ALL(:ALL)?\)\s+ALL' /etc/sudoers; then usermod -aG sudo '$og_user'; elif ! grep -Eiq 'user\s+ALL\s*=\s*\(ALL(:ALL)?\)\s+ALL' /etc/sudoers; then echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers; fi; exit" -

	if [ -x "$(command -v sudo)" ]; then
		echo "> Programm 'sudo' wurde erfolgreich installiert..."
	else
		echo "> Programm 'sudo' konnte nicht installiert oder gefunden werden..."
		exit 1
	fi

	echo "> $(Blue 'Hinweis:') Sie müssen sich nun einmalig ab- und wieder anmelden, um die neue Gruppenzugehörigkeit zu aktivieren."
	echo "  Die Zugehörigkeit in der Sudo-Gruppe ermöglicht es Ihnen, Befehle mit erweiterten Rechten ausführen zu können."
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

function remove_all_postgres_images() {
	echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Alle Postgres-Images löschen')
$(Dim $separator)

"

	echo -ne " $(Red 'WARNUNG')

   Sie sind im Begriff $(Red 'ALLE(!)') Postgres-Images endgültig zu entfernen!
   Dies betrifft auch Images, welche als Grundlage für einen laufenden und aktiven Container dienen.

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

	echo -ne "

   Dies ist $(Red 'die letzte Warnung!')
   Es werden ALLE(!) tote sowie aktive Images gelöscht! Dieser Schritt kann nicht rückgängig gemacht werden und
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

	docker rmi -f $(docker images | grep 'postgres')
}

function create_postgres_containers() {
	echo -ne "
$(Dim $separator)
$(Dim '# ')$(Blue 'Postgres-Container erstellen & starten')
$(Dim $separator)

"

	# Get currently highest port in use
	highest_port=$(("$(docker ps -a --format '{{.Image}} {{.Ports}}' | grep 'postgres:*' | grep -oP '(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]):\K([0-9]+)' | sort -n | tail -n 1)" + 1))

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
		echo "> $(Red 'Fehler:') Admin-Passwort darf nicht leer sein."
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

function is_user_in_group() {
	if id -nG "$1" | grep -qw "$2"; then
    	return 0
	fi

	return 1
}

function print_sys_info_headline() {
	# Docker Install Status
	docker_install=$(Dim 'Docker-Install  ')$(Red "$x_symbol")
	if [ -x "$(command -v docker)" ]; then
		docker_install=$(Dim 'Docker-Install  ')$(Green "$checkmark")
    fi

	# Docker Group
	docker_group=$(Dim 'Docker-Gruppe  ')$(Green "$checkmark")
	if ! is_user_in_group $USER 'docker'; then
		docker_group=$(Dim 'Docker-Gruppe  ')$(Red "$x_symbol")
	fi

	# Sudo Install Status
	sudo_install=$(Dim 'Sudo-Install  ')$(Red "$x_symbol")
	if [ -x "$(command -v sudo)" ]; then
		sudo_install=$(Dim 'Sudo-Install  ')$(Green "$checkmark")
    fi

	echo -ne "$docker_install  $docker_group  $sudo_install"
}

# menu prints the general and interactive navigation menu.
function menu(){
echo -ne "
$(Dim $separator)
$(Dim '#')
$(Dim '#') $(Blue 'Easy-Postgres-Containers '$version'')
$(Dim '#')
$(Dim '#') $(Dim 'Webseite:') $(Blue 'https://github.com/nikoksr/docker-scripts')
$(Dim '#') $(Dim 'Lizenz:')   $(Blue 'https://github.com/nikoksr/docker-scripts/LICENSE')
$(Dim '#')
$(Dim '#') $(print_sys_info_headline)
$(Dim '#')
$(Dim $separator)

$(Green '1)') Postgres-Container erstellen & starten
$(Green '2)') Alle Postgres-Container entfernen
$(Green '3)') Alle Postgres-Images entfernen
$(Green '4)') Docker installieren
$(Green '5)') Sudo installieren
$(Red '0)') Exit

$(Blue '>') "
    read a
    case $a in
		1) create_postgres_containers;;
		2) remove_all_postgres_containers;;
		3) remove_all_postgres_images;;
	    4) check_docker_install;;
		5) install_and_setup_sudo;;
		0) exit 0;;
		*) echo -e $red"Warnung: Option existiert nicht."$clear; menu;;
    esac
}

# entrypoint for the application.
function entrypoint(){
	trap "exit" INT
	menu
}

# Start the application.
entrypoint
