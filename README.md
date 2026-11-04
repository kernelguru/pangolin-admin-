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

## Projektstruktur

```
Packages/PangolinKit/   API-Client (Swift Package, plattformunabhängig, mit Tests)
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
