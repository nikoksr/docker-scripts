#!/usr/bin/env bash

##
# Variables
##

# Version
version='v0.1.0'

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

# check_deps checks if docker was installed correctly and installs it in case its missing.
function check_deps {
    echo "> Suche Paketmanager..."

    if [ -x "$(command -v pacman)" ]; then
        echo "> pacman gefunden..."
        echo ">   Installiere Docker..."
        sudo pacman -S --needed docker > /dev/null

    elif [ -x "$(command -v apt)" ] || [ -x "$(command -v apt-get)" ]; then
        echo "> apt gefunden..."
        if ! [ -x "$(command -v docker)" ]; then
            echo ">   Fehler: Es konnte keine Docker Installation gefunden werden."
            exit 1
        fi

    else
        echo "> Warnung: Es konnte kein unterstützter Paketmanager gefunden werden - Abhängigkeiten sind möglicherweise unvollständig und das weitere Vorgehen könnte fehlschlagen"
        echo "> Fahre fort..."
    fi
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

# menu prints the general and interactive navigation menu.
function menu(){
echo -ne "
$(DimText '#############################')
$(DimText '#')
$(DimText '# ')$(ColorBlue 'Easy-Docker '$version'')
$(DimText '#')
$(DimText '#############################')

$(ColorGreen '1)') Postgres Container erstellen
$(ColorGreen '2)') Checke Abhängigkeiten
$(ColorGreen '0)') Exit

$(ColorBlue '>') "
    read a
    case $a in
		1) create_postgres_container ;;
	    2) check_deps ;;
		0) exit 0 ;;
		*) echo -e $red"Warnung: Option existiert nicht."$clear ; menu ;;
    esac
}

# entrypoint for the application.
function entrypoint(){
	menu
}

# Start the application.
entrypoint
