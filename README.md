# Pangolin Admin (iOS)

Native iOS-Admin-App für einen **selbst gehosteten [Pangolin](https://github.com/fosrl/pangolin)-Server**, gebaut mit SwiftUI und dem Liquid-Glass-Design von iOS 26.
Die App spricht ausschließlich mit der **Pangolin Integration API (`/v1`)**.

## Funktionen

| Bereich | Möglich |
|---|---|
| Übersicht | Sites online/gesamt, Ressourcen-Health, Clients, Traffic, abgelehnte Requests (24 h), ausstehende Freigaben, ungeschützte Ressourcen – Auto-Refresh alle 30 s |
| Sites | Liste, Filter, Suche, Details, Neustart, Freigeben/Ablehnen, Umbenennen, Löschen |
| Ressourcen | Anlegen (HTTP mit Domain/Subdomain oder TCP/UDP mit Port, optional gleich mit Target), Health, Aktivieren/Deaktivieren, SSO, E-Mail-Whitelist, Zugriff blockieren, Löschen |
| Targets | Anlegen, Bearbeiten (Site, Protokoll, IP, Port), an/aus, Löschen |
| Authentifizierung | Passwort, 6-stelliger PIN und Header-Auth setzen, ersetzen, entfernen |
| Regeln | Anlegen, Bearbeiten, an/aus, Löschen (CIDR, IP, Pfad, Land, ASN, Region, Methode → Erlauben/Blockieren/Weiter) |
| Health-Checks | Liste mit Status, Anlegen/Bearbeiten (HTTP, TCP, Ping; Intervalle, Schwellwerte), an/aus, Löschen |
| Alert-Regeln | Liste, Anlegen/Bearbeiten (Ereignis, Quellen, Benutzer/Rollen/E-Mails, Webhooks, Pause), an/aus, Löschen |
| Clients | Liste, Filter (Geräte/Maschinen/gesperrt), Sperren/Entsperren, Archivieren, Löschen |
| Benutzer | Liste mit Rollen/2FA, Rollen zuweisen/entziehen, aus Org entfernen, einladen (Link teilen) |
| Weitere | Einladungen, Rollen, Domains, Protokolle (Anfragen, Zugriffe, Änderungen) |
| Server | Mehrere Server/Organisationen, Root-Key-Unterstützung mit Org-Wechsel |
| Server-Update (SSH) | Docker-Host per SSH (CA-Zertifikat, Secure-Enclave-Schlüssel), Compose-Datei automatisch finden, neue Versionen (GitHub + Docker-Hub-Prüfung), Update mit Sicherung, Live-Log, Zurückrollen |

## Projektstruktur

```
Packages/PangolinKit/   Swift Package (plattformunabhängig, mit Tests)
  Sources/PangolinKit             API-Client für die Integration API
  Sources/PangolinSSH             SSH-Client (Apple swift-nio-ssh): Zertifikate, Secure Enclave, Exec
  Sources/PangolinUpdater         Compose-Analyse, Versionssuche, Update-/Rollback-Skripte
  Sources/PangolinKit/Core        HTTP, Envelope, Fehler, tolerantes Decoding
  Sources/PangolinKit/Models      Site, PublicResource, Target, Client, OrgUser, Role, …
  Sources/PangolinKit/Endpoints   Alle Endpunkte als async-Methoden
  Sources/PangolinKit/Security    KeychainStore
App/Sources/            SwiftUI-App
project.yml             XcodeGen-Projektdefinition (das .xcodeproj wird generiert)
.github/workflows/      CI: Tests + unsigned IPA
```

## Server vorbereiten

1. In der Pangolin-`config.yml` die Integration API aktivieren:
   ```yaml
   flags:
     enable_integration_api: true
   server:
     integration_port: 3003   # Standard
   ```
2. Port 3003 per Traefik unter eigener Domain veröffentlichen (z. B. `https://api.example.com` → `http://pangolin:3003`), siehe [Pangolin-Doku](https://docs.pangolin.net/self-host/advanced/integration-api).
3. API-Schlüssel anlegen:
   - **Org-Schlüssel**: Organisation → API Keys. Funktioniert für genau eine Organisation; die Org-ID muss in der App eingetragen werden.
   - **Root-Schlüssel**: Server Admin → API Keys. Kann alle Organisationen auflisten (`/orgs`) und wechseln.
   - Berechtigungen nach Bedarf wählen. Für den vollen Funktionsumfang: Sites, Ressourcen, Targets, Clients, Benutzer, Rollen, Einladungen, Domains, Logs (lesen und schreiben).

## API-Client verwenden

```swift
import PangolinKit

let client = PangolinClient(configuration: .init(
    baseURL: URL(string: "https://api.example.com/v1")!,
    apiKey: try KeychainStore().read(profileID) ?? ""
))

let sites = try await client.allSites(orgId: "homelab")
try await client.restartSite(sites[0].siteId)
try await client.setResourceEnabled(7, enabled: false)
let logs = try await client.requestLogs(orgId: "homelab", .last(hours: 24))
```

Alle Methoden werfen `PangolinError` (`unauthorized`, `forbidden`, `notFound`, `server`, `decoding`, `transport`, …) mit deutschen Fehlermeldungen.
Das Decoding ist bewusst tolerant (`0/1` ↔ `Bool`, Zahlen als String, unbekannte Felder, kaputte Einzelelemente), da die API laut Pangolin noch Breaking Changes haben kann.

## API-Schlüssel & Keychain

- Gespeichert als `kSecClassGenericPassword`, Service `pangolin-admin.api-keys`, Account = UUID des Server-Profils.
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: nur bei entsperrtem Gerät lesbar, keine iCloud-Synchronisation, nicht in Backups auf andere Geräte übertragbar.
- Server-Profile (Name, URL, Org-ID) liegen ohne Geheimnis in `UserDefaults`.
- Beim Löschen eines Profils wird der Keychain-Eintrag entfernt.

## Bauen

### Lokal (Xcode 26)

```bash
brew install xcodegen
xcodegen generate
open PangolinAdmin.xcodeproj
```

Tests des API-Clients (auch unter Linux lauffähig):

```bash
swift test --package-path Packages/PangolinKit
```

### GitHub Actions → unsigned IPA

Der Workflow `.github/workflows/build-ipa.yml` läuft auf `macos-15-intel` mit Xcode 26 (Runner über die Repo-Variable `MACOS_RUNNER` oder beim manuellen Start änderbar) bei jedem Push, Pull Request oder manuell (*Actions → Build unsigned IPA → Run workflow*):

1. `swift test` für PangolinKit
2. `xcodegen generate`
3. `xcodebuild … CODE_SIGNING_ALLOWED=NO` (Release, `iphoneos`)
4. `Payload/PangolinAdmin.app` → `PangolinAdmin-<version>-<run>-unsigned.ipa`
5. Upload als Workflow-Artefakt (30 Tage); bei Tags `v*` zusätzlich als Release-Asset.

Die IPA ist **nicht signiert** und muss vor der Installation signiert werden, z. B. mit AltStore/SideStore, Sideloadly oder `codesign` mit eigenem Zertifikat. Die Keychain funktioniert nach dem Signieren normal.

## Einschränkungen der Integration API

- Kein Push/Streaming: Status und Traffic werden per Polling aktualisiert.
- `/orgs` nur mit Root-Schlüssel.
- Login per Benutzername/Passwort/SSO ist über die Integration API nicht möglich – nur API-Schlüssel.
- Die API ist als „pre-release“ markiert; nach Pangolin-Updates bitte Funktion prüfen.

## Server-Update per SSH

Unter **Mehr → Server-Update (SSH)** aktualisiert die App den Docker-Stack von Pangolin.

### Einrichtung

1. **Schlüssel:** In der App „Neuen Schlüssel in der Secure Enclave erzeugen“ (empfohlen – der private Schlüssel verlässt das iPhone nie) oder einen vorhandenen unverschlüsselten OpenSSH-Schlüssel (ed25519/ECDSA) importieren.
2. **Zertifikat:** Öffentlichen Schlüssel als `pangolin-admin.pub` speichern und mit der SSH-CA signieren:
   ```bash
   ssh-keygen -s /pfad/zur/ca -I pangolin-admin-iphone -n <benutzer> -V +52w pangolin-admin.pub
   ```
   Inhalt von `pangolin-admin-cert.pub` in der App einfügen. Der Server muss der CA vertrauen (`TrustedUserCAKeys` in `sshd_config`). Alternativ geht der öffentliche Schlüssel in `~/.ssh/authorized_keys`.
3. **Host-Schlüssel:** Beim ersten Verbinden zeigt die App den Fingerprint des Servers (vergleichen mit `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`). Danach werden nur noch Verbindungen mit genau diesem Schlüssel akzeptiert.
4. **Rechte:** Der Benutzer braucht Docker-Zugriff (Gruppe `docker` oder root). Sonst nutzt die App `sudo -n` – dafür ist eine NOPASSWD-Regel nötig.

### Ablauf

1. Die App findet den Pangolin-Container und über die Compose-Labels die `docker-compose.yml`.
2. Für bekannte Images (pangolin inkl. `ee-`/`postgresql-`-Varianten, gerbil, traefik, crowdsec, newt) sucht sie die neueste Version auf GitHub und prüft, ob das Tag auf Docker Hub existiert. Hauptversionssprünge (z. B. Traefik v3 → v4) sind standardmäßig abgewählt.
3. Update auf dem Server (losgelöst von der SSH-Sitzung, läuft also weiter, wenn die App in den Hintergrund geht):
   - Sicherung nach `pangolin-admin-backups/<Zeitstempel>/` (Compose-Datei, `.env`, Konfiguration, bei Postgres zusätzlich `pg_dumpall`)
   - nur die betroffenen `image:`-Zeilen ändern (Zeile wird vorher geprüft), `docker compose config` validieren
   - `docker compose pull` – der Stack läuft dabei weiter; bei Fehlern wird die Compose-Datei zurückgesetzt
   - `docker compose stop`, `config/` (inkl. SQLite-Datenbank) konsistent sichern, `docker compose up -d`
4. Danach prüft die App, ob die Integration API wieder antwortet. Jede Sicherung kann per „Zurückrollen“ wiederhergestellt werden.

### Tests

Die SSH-Tests laufen gegen einen echten OpenSSH-Server mit CA:

```bash
D=$(mktemp -d) && Packages/PangolinKit/scripts/ssh-test-server.sh "$D"
PANGOLIN_SSH_TEST_DIR="$D" swift test --package-path Packages/PangolinKit
kill "$(cat "$D/sshd.pid")"
```

Die Update-Skripte werden in den Tests tatsächlich mit `/bin/sh` gegen eine Compose-Datei und ein Fake-`docker` ausgeführt.
