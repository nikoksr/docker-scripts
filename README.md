# docker-scripts

Eine kleine Sammlung von Skripten, die versuchen, die Verwendung von Dockern in meist speziellen Anwendungsfällen zu vereinfachen.

> Just a small collection of scripts that try to simplify the use of docker in mostly special use cases.

## Easy-Postgres-Containers

Interaktives Shell-Menü zum vereinfachten Erzeugen, Listen, Entfernen und Beobachten von Postgres-Containern.

### Feature

-   Postgres-Container erstellen & starten
-   Postgres-Container auflisten
-   Postgres-Container Statistiken
-   Postgres-Container Log
-   Postgres-Container Top
-   Alle Postgres-Container entfernen
-   Ungenutzte Postgres-Images entfernen
-   `Docker` und automatisch installieren & konfigurieren

> Automatische Docker Installation ist aktuell unter Ubuntu (& Ubuntu-Forks), Debian (& Debian-Forks), CentOS, Fedora und Arch Linux unterstützt.

### Abhängigkeiten

Sollte der Skript dafür verwendet werden, um Docker zu installieren, werden `root`-Rechte
benötigt. Sie sollten dazu das Programm `sudo` installiert und ihrem aktuellen Benutzer
die Rechte gegeben haben, dieses Programm verwenden zu drüfen.

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

    curl -o epc.sh https://raw.githubusercontent.com/nikoksr/docker-scripts/main/epc.sh

oder

    wget https://raw.githubusercontent.com/nikoksr/docker-scripts/main/epc.sh

### Ausführen

    bash epc.sh

oder

    chmod +x epc.sh

    ./epc.sh
