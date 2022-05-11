# docker-scripts

Eine kleine Sammlung von Skripten, die versuchen, die Verwendung von Dockern in meist speziellen Anwendungsfällen zu vereinfachen.

> Just a small collection of scripts that try to simplify the use of docker in mostly special use cases.

## Easy-Postgres-Containers

Interaktives Shell-Menü zum vereinfachten Erzeugen, Listen, Entfernen und Beobachten von Postgres-Containern.

### Feature

-   `Docker` automatisch installieren & konfigurieren
-   Postgres-Container erstellen & starten
-   Postgres-Container auflisten
-   Postgres-Container Statistiken
-   Postgres-Container Log
-   Postgres-Container Top
-   Gestoppte Container entfernen
-   Unreferenzierte Images entfernen

### Abhängigkeiten

Sollte der Skript dafür verwendet werden, um Docker zu installieren, werden `root`-Rechte
benötigt. Sie sollten dazu das Programm `sudo` installiert und ihrem aktuellen Benutzer
die Rechte gegeben haben, dieses Programm verwenden zu dürfen.

Sollte das Installieren des `sudo` Programmes aus irgendwelchen Gründen nicht möglich sein,
können Sie auch auf den Benutzer `root` zurückgreifen. Es wird jedoch deutlich dazu geraten,
das Programm `sudo` vorzugsweise zu verwenden.

Zum Downloaden des Skripts wird entweder das Programm `curl` oder `wget` benötigt.

##### Ubuntu & Debian

    apt-get install curl

##### RHEL / CentOS / Fedora

    yum install curl

##### Arch

    pacman -S curl

### Download

> Sollten die gekürzten URLs nicht funktionieren, können Sie auch die vollständige URL verwenden: <https://raw.githubusercontent.com/nikoksr/docker-scripts/main/epc.sh>

    curl -sfL -o epc.sh https://git.io/JoU4N

oder

    wget -O epc.sh https://git.io/JoU4N

### Ausführen

    bash epc.sh

oder

    chmod +x epc.sh

    ./epc.sh
