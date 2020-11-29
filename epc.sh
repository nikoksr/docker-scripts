#!/usr/bin/env bash

##
# Variables
##

# Version
version='v0.3.0'

# Colors
green='\e[32m'
blue='\e[34m'
red='\e[31m'
dim='\e[2m'
undim='\e[22m'
clear='\e[0m'

##
# Color Functions
##
ColorGreen(){
	echo -ne $green$1$clear
}

ColorBlue(){
	echo -ne $blue$1$clear
}

DimText(){
	echo -ne $dim$1$clear
}

##
# Functions
##

# check_docker_install checks if docker was installed correctly and installs it in case its missing.
function check_docker_install {
	if [ -x "$(command -v docker)" ]; then
		echo "> Docker Installation gefunden..."
        return 0
    fi

	echo "> Bereite Docker Installation vor..."
    echo "> Suche Paketmanager..."

    if [ -x "$(command -v pacman)" ]; then
        echo ">   pacman gefunden..."
        sudo pacman -S --needed docker > /dev/null

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

	# Enable docker to start on boot
	echo ">   Aktiviere Docker-Service Autostart beim Boot..."
	sudo systemctl enable docker > /dev/null
}

function install_docker_apt() {
	echo ">     Update apt package index und installiere nötige Pakete um HTTPS Repository benutzen zu können..."

	sudo apt-get update
	sudo apt-get install \
    	apt-transport-https \
    	ca-certificates \
    	curl \
    	gnupg-agent \
    	software-properties-common \
		> /dev/null

	echo ">     Füge Docker's offiziellen GPG Key hinzu..."
	curl -fsSL "https://download.docker.com/linux/$1/gpg" | sudo apt-key add - > /dev/null

	echo ">     Füge Docker-Stable Apt-Repository hinzu..."
	sudo add-apt-repository \
   		"deb [arch=amd64] https://download.docker.com/linux/$1 \
   		$(lsb_release -cs) \
   		stable" \
		> /dev/null

	echo ">     Installiere Docker Engine..."
	sudo apt-get update > /dev/null
	sudo apt-get install docker-ce docker-ce-cli containerd.io > /dev/null
}

function install_docker_dnf() {
	echo ">     Füge Docker-Stable Dnf-Repository hinzu..."
	sudo dnf -y install dnf-plugins-core > /dev/null
	sudo dnf config-manager \
    	--add-repo \
    	https://download.docker.com/linux/fedora/docker-ce.repo \
		> /dev/null

	echo ">     Bei Fedora 31 oder höher muss die 'backward compatibility für Cgroups' freigeschaltet werden."
	echo ">     In dem Fall den folgenden Befehl ausführen und System neustarten: "
	echo '>     sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"'

	echo ">     Starte Docker Service..."
	sudo systemctl start docker > /dev/null
}

function install_docker_yum() {
	echo ">     Füge Docker-Stable Yum-Repository hinzu..."
	sudo yum install -y yum-utils
	sudo yum-config-manager \
    	--add-repo \
    	https://download.docker.com/linux/centos/docker-ce.repo \
		> /dev/null

	echo ">     Installiere Docker Engine..."
	sudo yum install docker-ce docker-ce-cli containerd.io > /dev/null

	echo ">     Starte Docker Service..."
	sudo systemctl start docker > /dev/null
}

function add_docker_group() {
	echo ">     Erstelle docker Gruppe..."
	sudo groupadd docker > /dev/null

	echo ">     Füge aktuellen Benutzer zur Gruppe hinzu..."
	sudo usermod -aG docker $USER > /dev/null

	echo ">     Es wird versucht die Gruppen-Änderung zu aktivieren. Sollte dies nicht funktionieren, müssen Sie sich einmal ab- und wieder anmelden."
	echo ">     Die Gruppe dient dazu, dass Docker ohne root-Rechte verwendet werden kann."
	newgrp docker
}

function create_postgres_container() {
	echo -ne "
$(DimText '################################')
$(DimText '# ')$(ColorBlue 'Postgres Container erstellen')
$(DimText '################################')

"

	# Name, Port and Postgres Version
	read -p "Container Name:            " container_name
	read -p "Externer Port (5432):      " external_port
	read -p "Postgres Version (latest): " postgres_version

	if [ -z "$external_port" ]; then
    	external_port="5432"
	fi

	if [ -z "$postgres_version" ]; then
    	postgres_version="latest"
	fi

	# Restart policy
	restart="always"
	echo
	echo -ne "Neustart Verhalten:

	$(ColorGreen '    1)') Immer (Standard)
	$(ColorGreen '    2)') Nur bei Absturz/Fehler
	$(ColorGreen '    3)') Immer, außer wenn explizit gestoppt
	$(ColorGreen '    4)') Nie
	$(ColorBlue '     >') "
	read a
    case $a in
		2) restart="on-failure";;
		3) restart="unless-stopped";;
		4) restart="no";;
		*);;
    esac

	# Set the command together
	exec_command="docker run --name $container_name -p $external_port:5432 --restart=$restart -d postgres:$postgres_version"

	if [ -z "$container_name" ]; then
    	exec_command="docker run -p $external_port:5432 --restart=$restart -d postgres:$postgres_version"
	fi

	echo
	echo
	echo "Vollständiger Befehl: $exec_command"
	echo
	read -p "Ausführen (J/n): " run
	case $run in
		"n");;
		"N");;
		*) $exec_command;;
    esac
}

function create_multiple_postgres_container() {
	echo -ne "
$(DimText '####################################################')
$(DimText '# ')$(ColorBlue 'Mehrere Postgres Container automatisch erstellen')
$(DimText '####################################################')

"

	# Anzahl, Port and Postgres Version
	read -p "Anzahl Container:           " container_count
	read -p "Start Port (5432):          " external_port
	read -p "Postgres Version (latest):  " postgres_version

	if [ -z "$container_count" ]; then
    	container_count=1
	fi

	if [ -z "$external_port" ]; then
    	external_port="5432"
	fi

	if [ -z "$postgres_version" ]; then
    	postgres_version="latest"
	fi

	# Restart policy
	restart="always"
	echo
	echo -ne "Neustart Verhalten:
$(ColorGreen '  1)') Immer (Standard)
$(ColorGreen '  2)') Nur bei Absturz/Fehler
$(ColorGreen '  3)') Immer, außer wenn explizit gestoppt
$(ColorGreen '  4)') Nie
$(ColorBlue '   >') "
	read a
    case $a in
		2) restart="on-failure";;
		3) restart="unless-stopped";;
		4) restart="no";;
		*);;
    esac

	# Database name
	echo
	read -p "Datenbank Name:             " db_name

	if [ -z "$db_name" ]; then
    	db_name="postgres_$(date +%s)"
	fi

	echo
	echo

	# Create multiple containers
	ip=$(ip route get 1.1.1.1 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}')
	end_port=$((external_port + container_count - 1))

	for port in `seq $external_port $end_port`; do
		$(docker run --name $name -p $port:5432 --restart=$restart -d postgres:$postgres_version > /dev/null) && \
		$(docker exec -it yournamecontainer psql -U postgres -c "CREATE DATABASE $db_name;" > /dev/null) && \
		echo "Postgres Container lauscht auf $ip:$port..."
		echo
    done
}

# menu prints the general and interactive navigation menu.
function menu(){
echo -ne "
$(DimText '####################################################')
$(DimText '#')
$(DimText '# ')$(ColorBlue 'Easy-Postgres-Containers '$version'')
$(DimText '#')
$(DimText '####################################################')

$(ColorGreen '1)') Mehrere Postgres Container automatisch erstellen
$(ColorGreen '2)') Einzelnen Postgres Container manuell erstellen
$(ColorGreen '3)') Docker Installation checken
$(ColorGreen '4)') User zu Docker Gruppe hinzufügen
$(ColorGreen '0)') Exit

$(ColorBlue '>') "
    read a
    case $a in
		1) create_multiple_postgres_container ;;
		2) create_postgres_container ;;
	    3) check_docker_install ;;
		4) add_docker_group ;;
		0) exit 0 ;;
		*) echo -e $red"Warnung: Option existiert nicht."$clear ; menu ;;
    esac
}

# entrypoint for the application.
function entrypoint(){
	trap "exit" INT
	menu
}

# Start the application.
entrypoint
