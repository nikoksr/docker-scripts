# docker-scripts

Eine kleine Sammlung von Skripten, die versuchen, die Verwendung von Dockern in meist speziellen Anwendungsfällen zu vereinfachen.

> Just a small collection of scripts that try to simplify the use of docker in mostly special use cases.

## Easy-Postgres-Containers

Interaktives Shell-Menü zum vereinfachten Erzeugen, Listen, Entfernen und Beobachten von Postgres-Containern.

### Feature

-   Einen oder mehrere Postgres-Container erstellen & starten
-   Postgres-Container auflisten
-   Postgres-Container beobachten
-   Postgres-Container Live Statistiken
-   Alle Postgres-Container entfernen
-   Alle Postgres-Images entfernen
-   `Docker` und `sudo` automatisch installieren & konfigurieren

### Download

    wget https://raw.githubusercontent.com/nikoksr/docker-scripts/main/epc.sh

### Ausführen

    bash epc.sh

oder

    chmod +x epc.sh

    ./epc.sh
