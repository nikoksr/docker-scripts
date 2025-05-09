#!/usr/bin/env bash

set -e

#################################################
# GLOBAL VARIABLES
#################################################

VERSION='v0.33.0-beta'

# This is the url to the official Docker install script which will be used here to.. install docker.
INSTALL_SCRIPT_URL="https://get.docker.com/"

# Name of the official postgres docker hub repo.
DOCKER_REPO_OFFICIAL="postgres"

# Name of a custom postgres docker hub repo. This usually supplies images that were customized. It is expected that the
# repo follows the tagging convention of the official repo and supports most or all major non-beta versions.
DOCKER_REPO_DEFAULT="nikoksr/postgres"

# Basically a clone of the default repo but used for testing purposes. It ususally contains the latest images.
DOCKER_REPO_EDGE="nikoksr/postgres-edge"

# Use the custom repo by default.
DOCKER_REPO="$DOCKER_REPO_DEFAULT"

# Keep track of CLI flags that were passed.
USE_OFFICIAL_REPO=0
USE_CUSTOM_REPO=0
USE_EDGE_REPO=0

# Shared memory size for the Docker container
DOCKER_SHM_SIZE=""

#################################################
# VISUALS
#################################################

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
green() { echo -e "$green$1$no_color"; }
blue() { echo -e "$blue$1$no_color"; }
red() { echo -e "$red$1$no_color"; }
dim() { echo -e "$dim$1$no_color"; }

parse_cli_arguments() {
    while [[ $# -gt 0 ]]; do
        arg="$1"
        case $arg in
        -h | --help)
            print_help
            exit 0
            ;;
        -v | --version)
            print_version
            exit 0
            ;;
        -o | --official-repo)
            DOCKER_REPO="$DOCKER_REPO_OFFICIAL"
            USE_OFFICIAL_REPO=1
            shift
            ;;
        -e | --edge-repo)
            DOCKER_REPO="$DOCKER_REPO_EDGE"
            USE_EDGE_REPO=1
            shift
            ;;
        -c | --custom-repo)
            if [[ -n "$2" && "$2" != -* ]]; then
                DOCKER_REPO="$2"
                USE_CUSTOM_REPO=1
                shift
                shift
            else
                echo "$(red 'Fehler:') Option -c benötigt einen Repository-Namen." >&2
                exit 1
            fi
            ;;
        --shm-size)
            if [[ -n "$2" && "$2" != -* ]]; then
                DOCKER_SHM_SIZE="$2"
                shift
                shift
            elif [[ -n "$2" && "$2" == -* ]]; then
                echo "$(red 'Fehler:') Option --shm-size benötigt einen Wert, erhielt aber '$2', was wie eine weitere Option aussieht." >&2
                echo "Bitte geben Sie eine Größe an, z.B. '256m' oder '1g'." >&2
                exit 1
            else
                echo "$(red 'Fehler:') Option --shm-size benötigt einen Wert (z.B. 256m)." >&2
                exit 1
            fi
            ;;
        *)
            shift
            ;;
        esac
    done

    if [ $((USE_OFFICIAL_REPO + USE_EDGE_REPO + USE_CUSTOM_REPO)) -gt 1 ]; then
        echo "$(red 'Fehler:') Optionen -o, -e und -c sind nicht kompatibel. Bitte wählen Sie nur eine Option aus."
        exit 1
    fi
}

print_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Einfache PostgreSQL-Container Erstellung und Verwaltung."
    echo
    echo "Options:"
    echo "  -h, --help                 Diese Hilfe anzeigen"
    echo "  -v, --version              Die Version dieses Scripts anzeigen"
    echo "  -o, --official-repo        Das offizielle Postgres Docker-Repo verwenden ($DOCKER_REPO_OFFICIAL)"
    echo "  -e, --edge-repo            Die neuesten Postgres Versionen verwenden ($DOCKER_REPO_EDGE)"
    echo "  -c, --custom-repo <repo>   Ein benutzerdefiniertes Postgres Docker-Repo verwenden (z.B. $DOCKER_REPO_DEFAULT)"
    echo "  --shm-size <size>          Die Größe des Shared Memory für den Container festlegen (z.B. 256m, 1g)."
    echo "                             Standardmäßig wird die Docker-Standardeinstellung verwendet."
    echo
    echo "Hinweis:"
    echo "  Standardmäßig wird das Docker-Repo 'nikoksr/postgres' verwendet. Dieses Repo enthält Postgres"
    echo "  Images, deren Encoding auf 'de_DE.UTF-8' eingestellt sind. Sie sind also für die Verwendung mit"
    echo "  der deutschen Sprache optimiert."
    echo
    echo "  Die Repos Official und Edge sind nicht identisch! Official ist das offizielle Postgres-Repo,"
    echo "  es enthält alle Versionen, die von der PostgreSQL-Community unterstützt werden. Edge ist ein"
    echo "  weiteres benutzerdefiniertes Repo, ähnlich dem Standard-Repo, das jedoch die neuesten Versionen"
    echo "  von Postgres enthält. Wurde eine neue Version von Postgres veröffentlicht, landet sie zuerst im"
    echo "  Edge-Repo. Sollten keine Probleme auftreten, wird sie dann in das Standard-Repo übertragen."
    echo
    echo "Beispiele:"
    echo "  # Verwende offizielle Postgres Images"
    echo "  $0 -o"
    echo
    echo "  # Verwende benutzerdefinierte Postgres Images"
    echo "  $0 -c johndoe/a-custom-postgres-repo"
    echo
    echo "  # Starte einen Container mit 512MB Shared Memory"
    echo "  $0 --shm-size 512m"
}

print_version() {
    echo "$VERSION"
}

print_header() {
    echo -ne "
$(dim $separator_thick)
$(dim '#')
$(dim '#') $(blue 'Easy-Postgres-Containers '$VERSION'')
$(dim '#')
$(dim '#') $(dim 'Autor:')  $(blue 'Niko Köser')
$(dim '#') $(dim 'Email:')  $(blue 'contact@nikoksr.dev')
$(dim '#') $(dim 'Lizenz:') $(blue 'https://github.com/nikoksr/docker-scripts/blob/main/LICENSE')
$(dim '#') $(dim 'Source:') $(blue 'https://github.com/nikoksr/docker-scripts/blob/main/epc.sh')
$(dim '#')
$(dim $separator_thick)"
}

menu() {
    local chosen_function
    local bad_choice=1

    while [ "$bad_choice" == 1 ]; do
        bad_choice=0
        # No clear here, header is printed, then menu. Clear is done in entrypoint once.
        print_header
        echo -e "$message" # message is for errors from previous attempt
        message=""

        echo -ne "
$(green '1)') Postgres-Container erstellen & starten
$(green '2)') Postgres-Container auflisten
$(green '3)') Postgres-Container Statistiken $(dim '(Live-Ansicht)')
$(green '4)') Postgres-Container Logs
$(green '5)') Postgres-Container Prozesse $(dim '(Live-Ansicht)')
$(green '6)') Gestoppte Postgres-Container entfernen
$(green '7)') Unreferenzierte Postgres-Images entfernen
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
        0) exit 0 ;; # Exit script directly
        *)
            bad_choice=1
            clear # Clear only if bad choice, to reprint header and menu
            message="\n\n$(red 'Warnung:') Ungültige Option gewählt."
            ;;
        esac
    done

    # Good choice; execute the chosen function
    clear        # Clear screen before executing the chosen action's specific UI
    print_header # Re-print header for the action's specific UI
    $chosen_function
    # After function executes, script will naturally end because menu() returns to entrypoint() which then ends.
}

#################################################
# HELPER FUNCS
#################################################

command_exists() { command -v "$@" >/dev/null 2>&1; }

get_timezone() {
    if filename=$(readlink /etc/localtime); then
        timezone=${filename#*zoneinfo/}
        if [[ $timezone = "$filename" || ! $timezone =~ ^[^/]+/[^/]+$ ]]; then
            # echo >&2 "$filename points to an unexpected location" # Suppress this error for cleaner output
            timezone="Europe/Berlin"
        fi
        echo "$timezone"
        return 0
    fi
    # Fallback to curl, then to default
    timezone=$(curl -fsSL 'https://ipapi.co/timezone' 2>/dev/null || echo "Europe/Berlin")
    echo "$timezone"
    return 0
}

is_user_root() { if [ "$EUID" -eq 0 ]; then return 0; else return 1; fi; }

is_user_in_docker_group() {
    if id -nG "$USER" | grep -qw "docker"; then
        return 0
    fi
    return 1
}

are_permissions_sufficient() {
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

    if ! is_user_in_docker_group && ! is_user_root; then
        echo -ne "
$(dim $separator_thick)
$(dim '# ')$(blue 'Berechtigung')
$(dim $separator_thick)

Der aktuelle Benutzer muss entweder Mitglied der 'docker' Gruppe sein oder dieser Skript muss (vorzugsweise)
mit 'sudo' oder als 'root' Benutzer ausgeführt werden.
Um den aktuellen Benutzer zur Gruppe 'docker' hinzuzufügen, führen Sie folgenden Befehl aus und melden sich anschließend ab und wieder an:

  sudo usermod -a -G docker $USER

Beende Skript aufgrund von unzureichenden Berechtigungen.
"
        return 1
    else
        return 0
    fi
}

#################################################
# DOCKER & POSTGRES
#################################################

get_postgres_container_ids() {
    declare -n epc_postgres_containers_ref=$1
    epc_postgres_containers_ref=()

    local all_container_ids_images
    all_container_ids_images=$(docker ps -a --format "{{.ID}} {{.Image}}")

    if [ -z "$all_container_ids_images" ]; then
        return
    fi

    local temp_pg_ids=()
    while IFS= read -r line; do
        local container_id image_name_or_id
        container_id=$(echo "$line" | awk '{print $1}')
        image_name_or_id=$(echo "$line" | awk '{print $2}')

        if [[ "$image_name_or_id" == "postgres" ||
            "$image_name_or_id" == "$DOCKER_REPO_OFFICIAL"* ||
            "$image_name_or_id" == "$DOCKER_REPO_DEFAULT"* ||
            "$image_name_or_id" == "$DOCKER_REPO_EDGE"* ||
            "$image_name_or_id" == "$DOCKER_REPO"* ]]; then
            temp_pg_ids+=("$container_id")
            continue
        fi

        if [[ "$image_name_or_id" =~ ^[a-f0-9]{12,}$ ]]; then
            local repo_tags repo_digests
            repo_tags=$(docker image inspect --format='{{json .RepoTags}}' "$image_name_or_id" 2>/dev/null || echo "[]")
            repo_digests=$(docker image inspect --format='{{json .RepoDigests}}' "$image_name_or_id" 2>/dev/null || echo "[]")

            if echo "$repo_tags" | grep -q -E '"postgres:|"[^"]*postgres:|"[^"]*'"$DOCKER_REPO_DEFAULT"':|"[^"]*'"$DOCKER_REPO_EDGE"':' ||
                echo "$repo_digests" | grep -q -E '"postgres@|"[^"]*postgres@|"[^"]*'"$DOCKER_REPO_DEFAULT"'@|"[^"]*'"$DOCKER_REPO_EDGE"'@'; then
                temp_pg_ids+=("$container_id")
            fi
        fi
    done <<<"$all_container_ids_images"

    if [[ ${#temp_pg_ids[@]} -gt 0 ]]; then
        local unique_ids_str
        unique_ids_str=$(printf "%s\n" "${temp_pg_ids[@]}" | sort -u)
        mapfile -t epc_postgres_containers_ref <<<"$unique_ids_str"
    fi
}

container_filter_from_ids() {
    local container_ids_list=("$@")
    local filter_string=""

    if [ ${#container_ids_list[@]} -eq 0 ]; then
        echo "-f id=xxxxxxxxxxxx"
        return
    fi

    for id_val in "${container_ids_list[@]}"; do
        filter_string="${filter_string} -f id=${id_val}"
    done

    echo "$filter_string"
}

install_docker() {
    echo -ne "
$(dim '# ')$(blue 'Docker Installation')
$(dim $separator_thick)

$(dim "Hinweis: Dieser Vorgang kann einige Minuten dauern.")

"
    local download_command=""
    if command_exists wget; then
        download_command="wget -qO-"
    elif command_exists curl; then
        download_command="curl -fsSL"
    else
        echo -e "$(red 'Fehler:') Es wurde kein passender Downloader gefunden. Erlaubte Downloader: curl, wget"
        return 1 # Changed to return
    fi

    if command_exists systemctl && systemctl is-active --quiet docker.socket; then
        echo "$(dim 'Hinweis:') Stoppe docker.socket vor der Installation..."
        sudo systemctl stop docker.socket || echo "$(red 'Warnung:') Konnte docker.socket nicht stoppen."
    fi

    echo "$(dim 'Führe Docker Installationsskript aus...')"
    if ! sh <($download_command $INSTALL_SCRIPT_URL); then
        echo -e "\n$(red 'Warnung:') Exit-Code des Installers deutet auf Fehler im Installationsprozess hin." >&2
        echo "$(red '         -> Installation wahrscheinlich unvollständig.')" >&2
        return 1 # Changed to return
    fi
    echo "$(green 'Docker erfolgreich installiert.')"
    echo "$(dim 'Füge aktuellen Benutzer zur Docker-Gruppe hinzu (Abmeldung erforderlich, um wirksam zu werden)...')"
    sudo usermod -aG docker "$USER" || echo "$(red 'Warnung:') Konnte Benutzer nicht zur Docker-Gruppe hinzufügen. Bitte manuell ausführen: sudo usermod -aG docker $USER"
    return 0
}

is_docker_daemon_running() {
    if docker info >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

start_docker_daemon() {
    echo "$(dim 'Starte Docker Daemon...')"
    if command_exists systemctl; then
        if ! systemctl is-active --quiet docker.service; then
            sudo systemctl enable --now docker.service >/dev/null || {
                echo "$(red 'Fehler beim Aktivieren von docker.service.')"
                return 1
            }
        fi
    elif command_exists service; then
        if ! sudo service docker status >/dev/null 2>&1; then
            sudo service docker start >/dev/null || {
                echo "$(red 'Fehler beim Starten des Docker-Dienstes mit ''service''.')"
                return 1
            }
        fi
    else
        if ! pgrep -f dockerd >/dev/null; then
            echo "$(dim 'Versuche Docker Daemon im Hintergrund zu starten (sudo dockerd &)...')"
            sudo dockerd >/var/log/dockerd.log 2>&1 &
            sleep 5
        fi
    fi

    if ! is_docker_daemon_running; then
        echo "$(red 'Fehler:') Docker Daemon konnte nicht gestartet werden."
        echo "$(dim 'Überprüfen Sie die Logs (z.B. journalctl -u docker.service oder /var/log/dockerd.log).')"
        return 1
    fi
    echo "$(green 'Docker Daemon ist aktiv.')"
    return 0
}

pick_port() {
    local ports_in_use_arr=("$@")
    local candidate_port=5432

    declare -A used_ports_map
    for p in "${ports_in_use_arr[@]}"; do
        used_ports_map["$p"]=1
    done

    while [[ -n "${used_ports_map[$candidate_port]}" ]]; do
        candidate_port=$((candidate_port + 1))
        if [[ "$candidate_port" -gt 65535 ]]; then
            echo "$(red 'Fehler: Konnte keinen freien Port finden.')" >&2
            echo ""
            return 1
        fi
    done
    echo "$candidate_port"
    return 0
}

create_postgres_containers() {
    echo -ne "
$(dim '# ')$(blue 'Postgres-Container erstellen & starten')
$(dim $separator_thick)
$(dim "

Tipp: Drücken Sie 'Enter', um einen in Klammern stehenden
      Standardwert zu verwenden.")


$(blue "### Konfiguration")

"
    echo -ne "> Anzahl Container $(dim '(1)'):                          "
    read container_count
    if [ -z "$container_count" ]; then
        container_count=1
    elif ! [[ "$container_count" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "\n> $(red 'FEHLER'): Ungültige Anzahl '$container_count'\n"
        return 1
    fi

    local DEFAULT_CONTAINER_NAME_BASE="postgres"
    echo -ne "> Container Name $(dim '(Zufall)'):                       "
    read container_name_base
    if [ -z "$container_name_base" ]; then
        container_name_base="$DEFAULT_CONTAINER_NAME_BASE"
    fi

    echo
    local ports_in_use=()
    local used_ports_output
    used_ports_output=$(docker ps -a --format "{{.Ports}}" | grep -Eo '[0-9]+->[0-9]+/tcp' | sed -E 's/0.0.0.0://g; s/:::://g' | cut -d':' -f1 | cut -d'-' -f1 | sort -un)
    if [[ -n "$used_ports_output" ]]; then
        readarray -t ports_in_use <<<"$used_ports_output"
    fi

    local initial_external_port
    initial_external_port=$(pick_port "${ports_in_use[@]}")
    if [[ -z "$initial_external_port" ]]; then return 1; fi

    echo -ne "> Start Port $(dim '('"$initial_external_port"')'):                                   "
    read external_port
    if [ -z "$external_port" ]; then
        external_port=$initial_external_port
    elif ! [[ "$external_port" =~ ^[0-9]+$ && "$external_port" -ge 1024 && "$external_port" -lt 65536 ]]; then # Often <1024 are privileged
        echo -e "\n> $(red 'FEHLER'): Ungültiger Port '$external_port' (muss zwischen 1024 und 65535 liegen).\n"
        return 1
    fi

    echo
    echo -ne "> Postgres Version $(dim '(latest)'):                     "
    read postgres_version
    local default_postgres_version="latest"
    if [ -z "$postgres_version" ]; then
        postgres_version="$default_postgres_version"
    elif [[ ! "$postgres_version" =~ ^[a-zA-Z0-9._-]+$ ]]; then # Allow underscore for tags like 15-alpine_custom
        echo -e "\n> $(red 'FEHLER'): Ungültiges Format für Postgres Version '$postgres_version'\n"
        return 1
    fi

    default_log_file_num="3"
    echo
    echo -ne "> Maximal Anzahl Log Dateien $(dim '('$default_log_file_num')'):                "
    read max_log_file
    if [ -z "$max_log_file" ]; then
        max_log_file="$default_log_file_num"
    elif ! [[ "$max_log_file" =~ ^[0-9]+$ ]]; then
        echo -e "\n> $(red 'FEHLER'): Ungültige Anzahl für Log Dateien '$max_log_file', verwende Standard."
        max_log_file="$default_log_file_num"
    fi

    default_log_file_size="1g"
    echo -ne "> Maximale Größe einer Log-Datei $(dim '('$default_log_file_size')'):         "
    read max_log_file_size
    if [ -z "$max_log_file_size" ]; then
        max_log_file_size="$default_log_file_size"
    fi
    if [[ ! "$max_log_file_size" =~ ^[0-9]+[kmgKMG]{0,1}$ ]]; then
        echo
        echo "> $(red 'WARNUNG'): Fehlerhafte Größenangabe für Log-Datei Größe ('$max_log_file_size'), verwende Standard."
        max_log_file_size="$default_log_file_size"
        echo -ne "             -> Korrigierte maximale Log-Datei Größe: $(dim $max_log_file_size)\n"
        echo -ne "           Erlaubte Größenangaben: k $(dim '(Kilobyte)'), m $(dim '(Megabyte)'), g $(dim '(Gigabyte)')\n"
    fi

    default_timezone="$(get_timezone)"
    echo
    echo -ne "> Zeitzone $(dim '('"$default_timezone"')'):                      "
    read timezone
    if [ -z "$timezone" ]; then
        timezone="$default_timezone"
    fi

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
            echo -e "\n> $(red 'FEHLER'): Eingegebene Passwörter unterscheiden sich\n"
            return 1
        fi
    fi

    echo -ne "> Datenbank Name $(dim '(postgres)'):                     "
    read db_name
    if [ -z "$db_name" ]; then
        db_name="postgres"
    fi

    echo
    echo -ne "$(blue "### Postgres Image laden")\n\n"
    if ! docker pull "$DOCKER_REPO":"$postgres_version"; then
        echo -e "$(red 'Fehler:') Konnte Postgres Image '$DOCKER_REPO:$postgres_version' nicht laden."
        return 1
    fi

    echo -ne "\n$(blue "### Container starten")\n\n"
    ip=$(ip route get 1.1.1.1 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}' || echo "localhost")

    local current_external_port=$external_port
    for ((i = 0; i < container_count; i++)); do
        local assigned_port=$current_external_port
        local is_current_port_used=0
        for p_used in "${ports_in_use[@]}"; do
            if [[ "$p_used" -eq "$assigned_port" ]]; then
                is_current_port_used=1
                break
            fi
        done

        if [[ "$is_current_port_used" -eq 1 && "$i" -gt 0 ]]; then # Only auto-pick if not the first user-defined port
            echo -e "> $(red 'WARNUNG:') Port $assigned_port ist bereits belegt. Suche nächsten freien Port..."
            local temp_ports_for_pick=("${ports_in_use[@]}" "$assigned_port")
            assigned_port=$(pick_port "${temp_ports_for_pick[@]}")
            if [[ -z "$assigned_port" ]]; then
                echo "$(red 'Konnte keinen freien Port für weitere Container finden.')"
                continue
            fi # Skip this container
            echo -e "> $(blue 'Info:') Nächster Port für Container $((i + 1)) ist $assigned_port."
        elif [[ "$is_current_port_used" -eq 1 && "$i" -eq 0 ]]; then
            echo -e "> $(red 'FEHLER:') Der angegebene Start-Port $assigned_port ist bereits belegt."
            continue # Skip this container, or error out if only one
        fi

        local container_name
        if [[ "$container_count" -gt 1 ]]; then
            container_name="${container_name_base}_${RANDOM}"
            while docker ps -a --format '{{.Names}}' | grep -Eq "^${container_name}$"; do
                container_name="${container_name_base}_${RANDOM}"
            done
        else
            container_name="$container_name_base"
            if docker ps -a --format '{{.Names}}' | grep -Eq "^${container_name}$"; then
                echo -e "> $(red 'WARNUNG:') Ein Container mit dem Namen '$container_name' existiert bereits."
                container_name="${container_name_base}_${RANDOM}"
                echo -e "> $(blue 'Info:') Verwende stattdessen '$container_name'."
                if docker ps -a --format '{{.Names}}' | grep -Eq "^${container_name}$"; then
                    echo -e "> $(red 'FEHLER:') Konnte keinen eindeutigen Namen finden nach Konflikt."
                    continue # Skip this container
                fi
            fi
        fi

        local docker_run_opts=()
        docker_run_opts+=(--name "$container_name")
        docker_run_opts+=(--log-opt max-file="$max_log_file")
        docker_run_opts+=(--log-opt max-size="$max_log_file_size")
        docker_run_opts+=(--publish "$assigned_port":5432)
        docker_run_opts+=(--restart="$restart")
        docker_run_opts+=(-e "POSTGRES_PASSWORD=$admin_pwd")
        docker_run_opts+=(-e "TZ=$timezone")
        if [ -n "$DOCKER_SHM_SIZE" ]; then
            if [[ "$DOCKER_SHM_SIZE" =~ ^[1-9][0-9]*[bBkKmMgG]?$ || "$DOCKER_SHM_SIZE" =~ ^[1-9][0-9]*$ ]]; then
                docker_run_opts+=(--shm-size="$DOCKER_SHM_SIZE")
            else
                echo -e "\n> $(red 'WARNUNG'): Ungültiges Format für --shm-size CLI Option '$DOCKER_SHM_SIZE'."
                echo "> Erwartet z.B. '256m', '1G', '1024k' oder eine positive Zahl für Bytes."
                echo "> Die Option --shm-size wird für Container '$container_name' ignoriert."
            fi
        fi
        docker_run_opts+=(-d "$DOCKER_REPO":"$postgres_version")

        echo "> Starte Container $(dim "$container_name") auf Port $assigned_port..."
        if ! docker run "${docker_run_opts[@]}" >/dev/null; then
            echo -e "> $(red 'FEHLER:') Konnte Container '$container_name' nicht starten."
            echo "> Überprüfen Sie die Docker Logs für Details (z.B. Port- oder Namenskonflikte)."
            continue
        fi
        ports_in_use+=("$assigned_port")

        local attempts=30 db_created=0 current_attempt=0
        if [ -n "$db_name" ] && [ ! "$db_name" = "postgres" ]; then
            echo -e "> Versuche Datenbank $(dim "$db_name") in $(dim "$container_name") zu erstellen..."
            while [[ $current_attempt -lt $attempts ]]; do
                if ! docker ps -f name="^${container_name}$" -f status=running --format "{{.ID}}" | grep -q .; then
                    echo -e "> $(red 'WARNUNG:') Container $(dim "$container_name") läuft nicht mehr. Datenbankerstellung abgebrochen."
                    break
                fi
                if docker exec "$container_name" psql -U postgres -c "CREATE DATABASE \"$db_name\";" >/dev/null 2>&1; then
                    db_created=1
                    echo -e "> Datenbank $(dim "$db_name") erfolgreich erstellt in $(dim "$container_name")"
                    break
                fi
                sleep 1
                current_attempt=$((current_attempt + 1))
            done
            if [[ $db_created -eq 0 && $current_attempt -ge $attempts ]]; then
                echo -e "> $(red 'WARNUNG:') Datenbank $(dim "$db_name") konnte auch nach $attempts Versuchen nicht in $(dim "$container_name") erstellt werden."
            fi
        fi
        echo -e "> Container $(dim "$container_name") gestartet auf $(green "$ip":"$assigned_port")"
        echo
        current_external_port=$((assigned_port + 1))
    done
}

list_postgres_containers() {
    echo -ne "
$(dim '# ')$(blue 'Postgres-Container auflisten')
$(dim $separator_thick)

"
    local container_ids_arr=()
    get_postgres_container_ids container_ids_arr
    local filter_string_val
    filter_string_val=$(container_filter_from_ids "${container_ids_arr[@]}")

    if [[ "$filter_string_val" == "-f id=xxxxxxxxxxxx" && ${#container_ids_arr[@]} -eq 0 ]]; then
        echo "Keine Postgres-Container gefunden."
    else
        docker container ls -a --format 'table {{.ID}}\t{{.Image}}\t{{.RunningFor}}\t{{.Status}}\t{{.Ports}}\t{{.Names}}' $filter_string_val
    fi
}

postgres_containers_stats() {
    echo -ne "
$(dim '# ')$(blue 'Postgres-Container Statistiken (Live-Ansicht)')
$(dim $separator_thick)
$(dim "

Hinweis: Zeigt Live-Statistiken für alle erkannten Postgres-Container.
         Drücken Sie Strg+C zum Beenden.")

"
    local container_ids_arr=()
    get_postgres_container_ids container_ids_arr

    if [ ${#container_ids_arr[@]} -eq 0 ]; then
        echo "Keine laufenden oder gestoppten Postgres-Container für Statistiken gefunden."
        echo "$(dim 'Stellen Sie sicher, dass die Container mit diesem Skript oder einem bekannten Postgres-Image erstellt wurden.')"
        return
    fi

    if ! command_exists watch; then
        echo "$(red 'Fehler:') Der Befehl ''watch'' wurde nicht gefunden. Er ist für die Live-Ansicht erforderlich."
        echo "$(dim 'Bitte installieren Sie ''watch'' (z.B. ''sudo apt install watch'').')"
        local ids_for_stats_once="${container_ids_arr[*]}"
        if [ -n "$ids_for_stats_once" ]; then
            echo "$(dim 'Zeige Statistiken einmalig:')"
            docker stats --no-stream $ids_for_stats_once
        fi
        return
    fi

    local ids_for_stats_str="${container_ids_arr[*]}"

    # No clear here, menu function already cleared. Header is re-printed by menu.
    # This function's specific header is already printed above.
    # The watch command will take over the terminal.
    watch -n 1 "docker stats --no-stream $ids_for_stats_str"
}

postgres_containers_logs() {
    echo -ne "
$(dim '# ')$(blue 'Postgres-Container Logs')
$(dim $separator_thick)

"
    local container_ids_arr=()
    get_postgres_container_ids container_ids_arr
    local filter_string_val
    filter_string_val=$(container_filter_from_ids "${container_ids_arr[@]}")

    if [[ "$filter_string_val" == "-f id=xxxxxxxxxxxx" && ${#container_ids_arr[@]} -eq 0 ]]; then
        echo "Keine Postgres-Container gefunden."
        return
    else
        # List only ID, Image, Name, Status for brevity before asking for ID
        docker container ls -a $filter_string_val --format 'table {{.ID}}\t{{.Image}}\t{{.Names}}\t{{.Status}}'
    fi

    echo
    echo -ne "$(blue 'Container-ID oder Name eingeben')"
    echo
    read -p "> " id_or_name_input

    if [ -z "$id_or_name_input" ]; then
        echo "$(red 'Keine ID/Name eingegeben.')"
        return
    fi

    local target_container_id=""
    for cid_check in "${container_ids_arr[@]}"; do
        local cname_check
        # Fetch name only if cid_check is a valid container ID
        if docker ps -a --filter "id=$cid_check" --format "{{.ID}}" | grep -q .; then
            cname_check=$(docker ps -a --filter "id=$cid_check" --format "{{.Names}}" | head -n 1)
            if [[ "$cid_check" == "$id_or_name_input" || "$cname_check" == "$id_or_name_input" ]]; then
                target_container_id="$cid_check"
                break
            fi
        fi
    done

    if [[ -z "$target_container_id" ]]; then
        echo "$(red 'Fehler:') Die ID/Name '$id_or_name_input' gehört nicht zu den aufgelisteten Postgres-Containern oder ist ungültig."
        return
    fi

    echo
    read -p "> Live verfolgen (j/N)? " choice
    choice=${choice:-N}

    # Clear screen for logs display
    clear
    print_header
    echo -ne "
$(dim '# ')$(blue 'Logs für Container '$target_container_id)
$(dim $separator_thick)
"
    case $choice in
    [jJyY]) docker container logs --since 10m -f "$target_container_id" ;;
    *) docker container logs "$target_container_id" ;;
    esac
}

postgres_containers_top() {
    echo -ne "
$(dim '# ')$(blue 'Postgres-Container Prozesse (Live-Ansicht)')
$(dim $separator_thick)

"
    local container_ids_arr=()
    get_postgres_container_ids container_ids_arr
    local filter_string_val
    filter_string_val=$(container_filter_from_ids "${container_ids_arr[@]}")

    if [[ "$filter_string_val" == "-f id=xxxxxxxxxxxx" && ${#container_ids_arr[@]} -eq 0 ]]; then
        echo "Keine Postgres-Container gefunden."
        return
    else
        docker container ls -a $filter_string_val --format 'table {{.ID}}\t{{.Image}}\t{{.Names}}\t{{.Status}}'
    fi

    echo
    echo -ne "$(blue 'Container-ID oder Name eingeben')"
    echo
    read -p "> " id_or_name_input

    if [ -z "$id_or_name_input" ]; then
        echo "$(red 'Keine ID/Name eingegeben.')"
        return
    fi

    local target_container_id_top=""
    for cid_top_check in "${container_ids_arr[@]}"; do
        local cname_top_check
        if docker ps -a --filter "id=$cid_top_check" --format "{{.ID}}" | grep -q .; then
            cname_top_check=$(docker ps -a --filter "id=$cid_top_check" --format "{{.Names}}" | head -n 1)
            if [[ "$cid_top_check" == "$id_or_name_input" || "$cname_top_check" == "$id_or_name_input" ]]; then
                target_container_id_top="$cid_top_check"
                break
            fi
        fi
    done

    if [[ -z "$target_container_id_top" ]]; then
        echo "$(red 'Fehler:') Die ID/Name '$id_or_name_input' gehört nicht zu den aufgelisteten Postgres-Containern oder ist ungültig."
        return
    fi

    if ! command_exists watch; then
        echo "$(red 'Fehler:') Der Befehl ''watch'' wurde nicht gefunden. Er ist für die Live-Ansicht erforderlich."
        echo "$(dim 'Bitte installieren Sie ''watch''. Zeige Prozessliste einmalig:')"
        docker container top "$target_container_id_top" -eo pid,user,pcpu,pmem,vsz,rss,tty,stat,start,time,command
        return
    fi

    # Clear screen for watch display
    # Header is already printed by menu, this function's specific header is above.
    watch -n 1 "docker container top $target_container_id_top -eo pid,user,pcpu,pmem,vsz,rss,tty,stat,start,time,command"
}

remove_all_postgres_containers() {
    echo -ne "
$(dim '# ')$(blue 'Gestoppte Postgres-Container entfernen')
$(dim $separator_thick)

"
    local all_pg_ids=()
    get_postgres_container_ids all_pg_ids

    local stopped_pg_container_ids_arr=()
    if [[ ${#all_pg_ids[@]} -gt 0 ]]; then
        for id_to_check_rm in "${all_pg_ids[@]}"; do
            if docker ps -a --filter "id=$id_to_check_rm" --filter "status=exited" --format "{{.ID}}" | grep -q .; then
                stopped_pg_container_ids_arr+=("$id_to_check_rm")
            fi
        done
    fi

    if [ ${#stopped_pg_container_ids_arr[@]} -eq 0 ]; then
        echo "Keine gestoppten Postgres-Container zum Entfernen gefunden."
        return
    fi

    local filter_string_stopped_val
    filter_string_stopped_val=$(container_filter_from_ids "${stopped_pg_container_ids_arr[@]}")

    echo -ne "$(red 'Liste gestoppter Postgres-Container, die entfernt werden:')\n$separator_thin\n"
    docker container ls -a --format 'table {{.ID}}\t{{.Image}}\t{{.Names}}\t{{.Status}}' $filter_string_stopped_val
    echo -ne "$separator_thin\n\n"
    echo -ne " $(red 'WARNUNG')\n\n   Sie sind im Begriff $(red 'ALLE oben aufgelisteten') gestoppten Postgres-Container endgültig zu entfernen!\n\n"
    read -p "> Möchten Sie fortfahren (j/N)? " choice
    choice=${choice:-N}
    if [[ ! "$choice" =~ ^[jJyY]$ ]]; then
        echo "Abgebrochen."
        return
    fi

    echo -ne "\n   Dies ist $(red 'die letzte Warnung!')\n   Datenverlust ist eine mögliche Folge!\n\n"
    read -p "> Möchten Sie trotzdem fortfahren (j/N)? " choice
    choice=${choice:-N}
    if [[ ! "$choice" =~ ^[jJyY]$ ]]; then
        echo "Abgebrochen."
        return
    fi

    echo -e "\n> Entferne Container..."
    if docker container rm -f "${stopped_pg_container_ids_arr[@]}" >/dev/null; then
        echo "$(green 'Ausgewählte Container erfolgreich entfernt.')"
    else
        echo "$(red 'Fehler beim Entfernen einiger oder aller Container.')"
    fi
}

remove_dangling_images() {
    echo -ne "
$(dim '# ')$(blue 'Unreferenzierte Postgres-Images entfernen')
$(dim $separator_thick)

"
    local dangling_image_ids_arr=()
    local dangling_output
    # List all dangling images first
    dangling_output=$(docker images -f "dangling=true" --format "{{.ID}}")

    if [[ -n "$dangling_output" ]]; then
        readarray -t all_dangling_ids <<<"$dangling_output"
        # Heuristic: Check if any of these were *ever* tagged with something postgres-like
        # This is hard because dangling images have <none> repo and tag.
        # A simpler approach: list all dangling, warn user it's ALL dangling images.
        # The original script filtered by "reference=postgres" which is more specific.
        # Let's try to stick to "postgres" related dangling images if possible.
        # `docker images postgres -f dangling=true` was the original idea.

        local pg_dangling_output
        pg_dangling_output=$(docker images --filter "dangling=true" --filter "reference=postgres*" --format "{{.ID}}")
        if [[ -n "$pg_dangling_output" ]]; then
            readarray -t dangling_image_ids_arr <<<"$pg_dangling_output"
        fi
    fi

    if [ ${#dangling_image_ids_arr[@]} -eq 0 ]; then
        echo "Keine unreferenzierten Postgres-Images gefunden."
        return
    fi

    echo -ne "$(red 'WARNUNG')\n\n Sie sind im Begriff $(red 'alle unten aufgelisteten') unreferenzierten/dangling Postgres-Images zu entfernen!\n"
    echo -ne "\n$(red 'Liste unreferenzierter Postgres-Images:')\n$separator_thin\n"

    # Displaying these specific images
    docker images --filter "dangling=true" --filter "reference=postgres*" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}"

    echo -ne "$separator_thin\n\n"
    read -p "> Möchten Sie fortfahren (j/N)? " choice
    choice=${choice:-N}
    if [[ ! "$choice" =~ ^[jJyY]$ ]]; then
        echo "Abgebrochen."
        return
    fi

    echo -e "\n> Entferne Images..."
    echo -e "$(dim "Hinweis: Fehler beim Entfernen sind möglich, wenn ein Image noch (indirekt) verwendet wird.")\n"
    if docker image rm "${dangling_image_ids_arr[@]}" >/dev/null 2>&1; then # Suppress "Error: No such image" if already gone
        echo "$(green 'Ausgewählte unreferenzierte Images erfolgreich entfernt.')"
    else
        # Check if any images are left to confirm if it was a partial success or total failure
        local remaining_pg_dangling
        remaining_pg_dangling=$(docker images --filter "dangling=true" --filter "reference=postgres*" --format "{{.ID}}" -q)
        local still_to_remove=0
        for id_check_after_rm in "${dangling_image_ids_arr[@]}"; do
            if echo "$remaining_pg_dangling" | grep -q "$id_check_after_rm"; then
                still_to_remove=1
                break
            fi
        done
        if [[ $still_to_remove -eq 1 ]]; then
            echo "$(red 'Einige oder alle unreferenzierten Images konnten nicht entfernt werden.')"
        else
            echo "$(green 'Ausgewählte unreferenzierte Images erfolgreich entfernt.')" # All specified IDs are gone
        fi
    fi
}

#################################################
# ENTRYPOINT
#################################################

entrypoint() {
    # Trap Ctrl+C (SIGINT)
    trap "echo; echo '$(red 'Vorgang durch Benutzer abgebrochen.')'; exit 130" INT

    # Parse CLI arguments
    parse_cli_arguments "$@"

    # Check permissions
    if ! are_permissions_sufficient; then exit 1; fi

    # Install Docker if not found
    if ! command_exists docker; then
        echo "$(blue 'Docker nicht gefunden. Versuche Installation...')"
        install_docker || {
            echo "$(red 'Docker-Installation fehlgeschlagen.')"
            exit 1
        }
    fi

    # Start Docker daemon if not running
    if ! is_docker_daemon_running; then
        echo "$(blue 'Docker Daemon läuft nicht. Versuche zu starten...')"
        start_docker_daemon || {
            echo "$(red 'Starten des Docker Daemons fehlgeschlagen.')"
            exit 1
        }
    fi

    # Clear screen once before showing the main menu
    clear
    menu
}

entrypoint "$@"
