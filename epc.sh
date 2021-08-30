#!/usr/bin/env bash
set -e

####
#
# VARS
#
####

version='v0.25.0'

# Visual separation bar
separator_thick='######################################################################'
separator_thin='======================================================================'

# Colors codes
green='\e[32m'
blue='\e[96m'
red='\e[31m'
dim='\e[2m'
no_color='\e[0m'

# Color functions. Accept string and echo it in the respective color.
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

####
#
# HELPER FUNCTIONS
#
####

command_exists() {
	command -v "$@" >/dev/null 2>&1
}

get_timezone() {
	set -euo pipefail

	# Check if /etc/localtime is a symlink as expected
	if filename=$(readlink /etc/localtime); then
		timezone=${filename#*zoneinfo/}
		if [[ $timezone = "$filename" || ! $timezone =~ ^[^/]+/[^/]+$ ]]; then
			# not pointing to expected location or not Region/City
			echo >&2 "$filename points to an unexpected location"
			return 1
		fi

		echo "$timezone"
		return 0
	fi

	# Fallback; use ipapi to get timezone
	timezone=$(curl -s 'https://ipapi.co/timezone' >/dev/null)

	# Fallback to fixed default timezone.
	if [ -z "$timezone" ]; then
		timezone="Europe/Berlin"
	fi

	echo "$timezone"
	return 0
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
	if ! command_exists docker; then
		if is_user_root; then
			return 0
		fi
		echo -ne "
$(dim $separator_thick)
$(dim '# ')$(blue 'Docker Installation')
$(dim $separator_thick)

Docker ist enweder nicht installiert oder die Installation konnte nicht gefunden werden. Bitte starten
Sie den Skript (vorzugsweise) mit 'sudo' oder als 'root' Benutzer neu, um die automatische Installation
und Einrichtung von Docker zu starten.
"
		return 1
	fi

	# If docker service is not running, need root to start and enable service
	if ! is_docker_daemon_running; then
		if is_user_root; then
			return 0
		fi
		echo -ne "
$(dim $separator_thick)
$(dim '# ')$(blue 'Docker Installation')
$(dim $separator_thick)

Docker-Daemon scheint nicht aktiviert zu sein. Bitte starten Sie den Skript (vorzugsweise) mit 'sudo' oder
als 'root' Benutzer neu, um die automatische Aktivierung des Docker-Daemons zu starten.
"
		return 1
	fi

	# If docker is installed user has to be in docker group
	if ! is_user_in_docker_group && ! is_user_root; then
		echo -ne "
$(dim $separator_thick)
$(dim '# ')$(blue 'Berechtigung')
$(dim $separator_thick)

Der aktuelle Benutzer muss entweder Mitglied der 'docker' Gruppe sein oder dieser Skript muss (vorzugsweise)
mit 'sudo' oder als 'root' Benutzer ausgeführt werden.
Um den aktuellen Benutzer zur Gruppe 'docker' hinzuzufügen, führen Sie folgenden Befehl aus und melden sich anschließend ab und wieder an:

  usermod -a -G docker $USER

Beende Skript aufgrund von unzureichenden Berechtigungen.
"
		return 1
	else
		return 0
	fi
}

####
#
# DOCKER INSTALLATION
#
####

# This is the url to the official Docker install script which will be used here to.. install docker.
INSTALL_SCRIPT_URL="https://get.docker.com/"

install_docker() {
	echo -ne "
$(dim '# ')$(blue 'Docker Installation')
$(dim $separator_thick)

$(dim "> Dieser Vorgang kann einige Minuten dauern.")

"

	download_command=""
	if command_exists wget; then
		download_command="wget -qO-"
	elif command_exists curl; then
		download_command="curl -s"
	else
		echo -e "$red""Fehler: Es wurde kein passender Downloader gefunden. Erlaubte Downloader: curl, wget""$no_color"
		exit 1
	fi

	systemctl is-active --quiet docker.socket && systemctl stop --quiet docker.socket

	if ! sh <($download_command $INSTALL_SCRIPT_URL) >/dev/null; then

		echo -ne "
$(red 'Warnung:') Exit-Code des Installers deutet auf Fehler im Installationsprozess hin.
         -> Installation wahrscheinlich unvollständig.

"
		# Possible repair commands
		# dpkg --configure -a
		# apt install -f

		exit 1
	fi
}

is_docker_daemon_running() {
	if pgrep -f docker >/dev/null; then
		return 0
	fi
	return 1
}

start_docker_daemon() {
	if command_exists systemctl; then
		systemctl is-active --quiet docker.service || systemctl enable --now --quiet docker.service >/dev/null
	# elif command_exists service; then
	# 	service docker status > /dev/null || service docker start > /dev/null
	else
		pgrep -f docker >/dev/null || dockerd &
	fi
}

####
#
# CONTAINER MANIPULATION
#
####

create_postgres_containers() {
	echo -ne "
$(dim '# ')$(blue 'Postgres-Container erstellen & starten')
$(dim $separator_thick)
$(dim "

Tipp: Drücken Sie 'Enter', um einen in Klammern stehenden
      Standardwert zu verwenden.")


$(blue "### Konfiguration")

"

	# Anzahl, Port and Postgres Version
	echo -ne "> Anzahl Container $(dim '(1)'):                          "
	read container_count
	if [ -z "$container_count" ]; then
		container_count=1
	fi

	# Container name
	local DEFAULT_CONTAINER_NAME="postgres"
	echo -ne "> Container Name $(dim '(Zufall)'):                       "
	read container_name
	if [ -z "$container_name" ]; then
		container_name="$DEFAULT_CONTAINER_NAME"
	fi

	echo

	# Get currently highest port in use
	ports_list="$(docker ps -a --format '{{.Image}} {{.Ports}}' | grep -oP '(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]):\K([0-9]+)' | sort -n)"

	# Avoid globbing (expansion of *).
	set -f

	# Turn ports string into array
	ports_list=(${ports_list//\n/ })

	local highest_port=0

	for idx in "${!ports_list[@]}"; do
		# Last port reached; set port equal to last port + 1
		if [ -z "${ports_list[$((idx + 1))]}" ]; then
			highest_port=$(("${ports_list[idx]}" + 1))
			break
		fi

		# Check if all containers fit in port range
		if [[ ($(("${ports_list[idx]}" + "$container_count" + 1)) < ${ports_list[$((idx + 1))]}) ]]; then
			highest_port=$(("${ports_list[idx]}" + 1))
			break
		fi
	done

	# If no taken ports were detected use postgres default port as container port
	if [[ "$highest_port" -eq 0 ]]; then
		highest_port=5432
	fi

	echo -ne "> Port $(dim '('$highest_port')'):                                   "
	read external_port
	if [ -z "$external_port" ]; then
		external_port=$highest_port
	fi

	echo
	echo -ne "> Postgres Version $(dim '(latest)'):                     "
	read postgres_version
	if [ -z "$postgres_version" ]; then
		postgres_version="latest"
	fi

	# Logging behaviour
	echo
	echo -ne "> Maximal Anzahl Log Dateien $(dim '(5)'):                "
	read max_log_file
	if [ -z "$max_log_file" ]; then
		max_log_file="5"
	fi

	default_log_file_size="20m"
	echo -ne "> Maximale Größe einer Log-Datei $(dim '('$default_log_file_size')'):         "
	read max_log_file_size
	if [ -z "$max_log_file_size" ]; then
		max_log_file_size="$default_log_file_size"
	fi

	if [[ ! "$max_log_file_size" =~ ^[0-9]+[kmg]{0,1}$ ]]; then
		max_log_file_size="$default_log_file_size"
		echo
		echo "> WARNUNG: Fehlerhafte Größenangabe gefunden"
		echo "             -> Falle zurück auf Standardwert"
		echo -ne "             -> Korrigierte maximale Log-Datei Größe: $(dim $max_log_file_size)"
		echo
		echo
		echo -ne "           Erlaubte Größenangaben: k $(dim '(Kilobyte)'), m $(dim '(Megabyte)'), g $(dim '(Gigabyte)')"
		echo
	fi

	# Timezone
	default_timezone="$(get_timezone)"
	echo
	echo -ne "> Zeitzone $(dim '('"$default_timezone"')'):                      "
	read timezone
	if [ -z "$timezone" ]; then
		timezone="$default_timezone"
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
	2) restart="on-failure" ;;
	3) restart="unless-stopped" ;;
	4) restart="no" ;;
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

	# Follow an example request to find out systems IP address. 'ip a ' is too verbose and
	# shows ip addresses of ALL network interfaces on the system.
	ip=$(ip route get 1.1.1.1 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}')
	end_port=$((external_port + container_count - 1))

	local original_container_name="$container_name"

	for port in $(seq $external_port $end_port); do

		container_name="$original_container_name"
		if [[ "$container_count" -gt 1 || "$container_count" -eq 1 && "$container_name" == "$DEFAULT_CONTAINER_NAME" ]]; then
			container_name="${container_name}_$RANDOM"
		fi

		docker run \
			--name "$container_name" \
			--log-opt max-file="$max_log_file" \
			--log-opt max-size="$max_log_file_size" \
			--publish "$port":5432 \
			--restart="$restart" \
			-e POSTGRES_PASSWORD="$admin_pwd" \
			-e TZ="$timezone" \
			-d \
			postgres:"$postgres_version" >/dev/null

		# Only create database if name was given. Skip on empty.
		if [ -n "$db_name" ] && [ ! "$db_name" = "postgres" ]; then

			# Wait 90 seconds for container to start
			is_running=1
			while [[ $i -lt 90 ]]; do
				if [[ "$(docker exec $container_name pg_isready)" == *"accepting"* ]]; then
					is_running=0
					break
				fi
				sleep 1s
				i=$(("$i" + 1))
			done

			# Check if container is running and create database if so.
			if [ "$is_running" -eq 0 ]; then
				docker exec -it "$container_name" psql -U postgres -c "CREATE DATABASE $db_name;" &&
					echo "> Datenbank $db_name erfolgreich erstellt..."
			else
				echo "> $(red 'Warnung:') Konnte Datenbank nicht anlegen, da Container nicht im erwarteten Zeitraum gestartet ist..."
			fi
		fi

		echo -e "> Container $(dim $container_name) gestartet auf $(green "$ip":"$port")"
	done
	echo
}

remove_all_postgres_containers() {
	echo -ne "
$(dim '# ')$(blue 'Gestoppte Container entfernen')
$(dim $separator_thick)

"

	echo -ne "
$(red 'Liste gestoppter Container')
$separator_thin

"

	docker container ls -a -f "status=exited" --format "table {{.ID}}\t{{.Image}}\t{{.Names}}\t{{.RunningFor}}"

	echo -ne "
$separator_thin


"

	echo -ne " $(red 'WARNUNG')

   Sie sind im Begriff $(red 'ALLE(!)') gestoppten Container endgültig zu entfernen!


"

	read -p "> Möchten Sie fortfahren (j/N)? " choice

	if [ -z "$choice" ]; then
		choice="n"
	fi

	case $choice in
	"j" | "J" | "y" | "Y") ;;
	*) exit 0 ;;
	esac

	echo -ne "

   Dies ist $(red 'die letzte Warnung!')
   Es werden ALLE(!) gestoppten Container gelöscht! Dieser Schritt kann nicht
   rückgängig gemacht werden und $(red 'Datenverlust') ist eine mögliche Folge!


"

	read -p "> Möchten Sie trotzdem fortfahren (j/N)? " choice

	if [ -z "$choice" ]; then
		choice="n"
	fi

	case $choice in
	"j" | "J" | "y" | "Y") ;;
	*) exit 0 ;;
	esac

	echo "> Entferne Container"
	echo

	docker ps -a | awk '{ print $1,$2 }' | grep 'postgres:*' | awk '{print $1 }' | xargs -I {} docker rm -f {}
}

remove_dangling_images() {
	echo -ne "
$(dim '# ')$(blue 'Unreferenzierte Images entfernen')
$(dim $separator_thick)


"

	echo -ne "$(red 'WARNUNG')

 Sie sind im Begriff $(red 'alle') unreferenzierten/dangling Docker-Images zu entfernen!


"

	read -p "> Möchten Sie fortfahren (j/N)? " choice

	if [ -z "$choice" ]; then
		choice="n"
	fi

	case $choice in
	"j" | "J" | "y" | "Y") ;;
	*) exit 0 ;;
	esac

	echo "> Entferne Images"
	echo

	docker image prune -f
}

list_postgres_containers() {
	echo -ne "
$(dim '# ')$(blue 'Postgres-Container auflisten')
$(dim $separator_thick)

"
	docker ps | head -n1
	docker ps -a | grep 'postgres:*'
}

postgres_containers_stats() {
	watch -n 0 "docker stats --no-stream | head -n1 && docker stats --no-stream | grep 'postgres:*'"
}

postgres_containers_logs() {
	echo -ne "
$(dim '# ')$(blue 'Postgres-Container Logs')
$(dim $separator_thick)

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

	echo
	read -p "> Live verfolgen (j/N)? " choice

	if [ -z "$choice" ]; then
		choice="n"
	fi

	clear
	case $choice in
	"j" | "J" | "y" | "Y") docker container logs --since 0s -f "$id" ;;
	*) docker container logs "$id" ;;
	esac
}

postgres_containers_top() {
	echo -ne "
$(dim '# ')$(blue 'Postgres-Container Top')
$(dim $separator_thick)

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

####
#
# UI
#
####

print_header() {
	echo -ne "
$(dim $separator_thick)
$(dim '#')
$(dim '#') $(blue 'Easy-Postgres-Containers '$version'')
$(dim '#')
$(dim '#') $(dim 'Autor:')  $(blue 'Niko Köser')
$(dim '#') $(dim 'Email:')  $(blue 'contact@nikoksr.dev')
$(dim '#') $(dim 'Lizenz:') $(blue 'https://github.com/nikoksr/docker-scripts/blob/main/LICENSE')
$(dim '#') $(dim 'Source:') $(blue 'https://github.com/nikoksr/docker-scripts/blob/main/epc.sh')
$(dim '#')
$(dim $separator_thick)"
}

# menu prints the general and interactive navigation menu.
menu() {
	local chosen_function
	local bad_choice=1

	while [ "$bad_choice" == 1 ]; do
		# Reset choice to make the loop work.
		bad_choice=0

		print_header

		echo -e "$message"
		message=""

		echo -ne "
$(green '1)') Postgres-Container erstellen & starten
$(green '2)') Postgres-Container auflisten
$(green '3)') Postgres-Container Statistiken
$(green '4)') Postgres-Container Log
$(green '5)') Postgres-Container Top
$(green '6)') Gestoppte Container entfernen
$(green '7)') Unreferenzierte Images entfernen
$(red '0)') Exit

$(blue '>') "
		read choice
		case $choice in
		1) chosen_function=create_postgres_containers ;;
		2) chosen_function=list_postgres_containers ;;
		3) chosen_function=postgres_containers_stats ;;
		4) chosen_function=postgres_containers_logs ;;
		5) chosen_function=postgres_containers_top ;;
		6) chosen_function=remove_all_postgres_containers ;;
		7) chosen_function=remove_dangling_images ;;
		0) exit 0 ;;
		*)
			bad_choice=1
			clear
			message="\n\n$(red 'Warnung:') Ungültige Option gewählt."
			;;
		esac
	done

	# Good choice; execute the chosen funtion
	clear
	print_header
	$chosen_function
}

# entrypoint for the application.
entrypoint() {
	# Cancel on ctrl+c
	trap "exit" INT

	# Check if user permissions are sufficient
	if ! are_permissions_sufficient; then
		exit 1
	fi

	# Install docker if not already exists
	if ! command_exists docker; then
		install_docker
	fi

	# Start docker daemon if not already running
	if ! is_docker_daemon_running; then
		start_docker_daemon
	fi

	# Start options menu only(!) when dependencies are statisfied
	clear
	menu
}

# Start the application.
entrypoint
