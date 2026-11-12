import Foundation

/// Where newer versions of an image come from.
public enum VersionSource: Sendable, Hashable {
    /// GitHub releases of `owner/repo`.
    case githubReleases(owner: String, repo: String)

    /// Known images of a Pangolin stack. Other images are only re-pulled with their current tag.
    public static func forImage(_ image: ImageReference) -> VersionSource? {
        let repo = image.repository.lowercased()
        switch true {
        case repo.hasSuffix("fosrl/pangolin"): return .githubReleases(owner: "fosrl", repo: "pangolin")
        case repo.hasSuffix("fosrl/gerbil"): return .githubReleases(owner: "fosrl", repo: "gerbil")
        case repo.hasSuffix("fosrl/newt"): return .githubReleases(owner: "fosrl", repo: "newt")
        case repo == "traefik" || repo == "library/traefik": return .githubReleases(owner: "traefik", repo: "traefik")
        case repo.hasSuffix("crowdsecurity/crowdsec"): return .githubReleases(owner: "crowdsecurity", repo: "crowdsec")
        default: return nil
        }
    }
}

/// What will happen to one image.
public struct ImageUpdate: Sendable, Hashable, Identifiable {
    public enum Action: Sendable, Hashable {
        /// Change the tag in the compose file.
        case retag(newTag: String, newVersion: SemanticVersion)
        /// Keep the tag, just pull (floating tags like `18`, `latest` or unknown images).
        case pullOnly
        /// Already on the newest version.
        case upToDate
        /// Newest version could not be determined.
        case unknown(String)
    }

    public var id: Int { image.id }
    public let image: ComposeImage
    public let currentVersion: SemanticVersion?
    public let latestVersion: SemanticVersion?
    public let action: Action
    /// The new tag was confirmed to exist on Docker Hub (nil = not checked).
    public var tagVerified: Bool?
    /// Major version jump (e.g. Traefik v3 → v4) – off by default.
    public var isMajorUpgrade: Bool {
        guard let currentVersion, let latestVersion else { return false }
        return latestVersion.major > currentVersion.major
    }

    public var newReference: String? {
        if case .retag(let tag, _) = action { return image.image.with(tag: tag) }
        return nil
    }

    public init(image: ComposeImage, currentVersion: SemanticVersion?, latestVersion: SemanticVersion?,
                action: Action, tagVerified: Bool? = nil) {
        self.image = image
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.action = action
        self.tagVerified = tagVerified
    }

    /// Decides the action for an image given the newest released version.
    public static func evaluate(_ image: ComposeImage, latest: SemanticVersion?) -> ImageUpdate {
        guard let versioned = image.image.versionedTag else {
            return ImageUpdate(image: image, currentVersion: nil, latestVersion: latest, action: .pullOnly)
        }
        guard let latest else {
            let action: Action = VersionSource.forImage(image.image) == nil
                ? .pullOnly : .unknown("Neueste Version nicht ermittelbar")
            return ImageUpdate(image: image, currentVersion: versioned.version, latestVersion: nil, action: action)
        }
        if latest > versioned.version {
            return ImageUpdate(image: image, currentVersion: versioned.version, latestVersion: latest,
                               action: .retag(newTag: versioned.tag(for: latest), newVersion: latest))
        }
        return ImageUpdate(image: image, currentVersion: versioned.version, latestVersion: latest, action: .upToDate)
    }
}

/// The change set the user confirmed.
public struct UpdatePlan: Sendable, Hashable {
    public struct Retag: Sendable, Hashable {
        public let lineNumber: Int
        public let oldReference: String
        public let newReference: String
    }

    public let deployment: PangolinDeployment
    public let retags: [Retag]
    /// Back up a Postgres database (`pg_dumpall`) if the stack has a postgres service.
    public let postgresService: String?

    public init(deployment: PangolinDeployment, updates: [ImageUpdate], selected: Set<Int>, postgresService: String?) {
        self.deployment = deployment
        self.retags = updates.compactMap { update in
            guard selected.contains(update.id), let new = update.newReference else { return nil }
            return Retag(lineNumber: update.image.lineNumber, oldReference: update.image.image.raw, newReference: new)
        }
        self.postgresService = postgresService
    }

    /// Finds a postgres service in the compose images.
    public static func postgresService(in images: [ComposeImage]) -> String? {
        images.first { $0.image.repository.lowercased().hasSuffix("postgres") }?.service
    }
}

/// Generates the shell scripts that run on the server.
///
/// Markers printed for the app: `PA_STEP=<name>`, `PA_BACKUP=<path>`, `PA_ERROR=<text>`.
public enum UpdateScript {
    public static let backupRoot = "pangolin-admin-backups"

    /// Defines `dc` (docker compose v2 or docker-compose v1) for this project.
    static func composeFunction(_ d: PangolinDeployment) -> String {
        let files = d.container.configFiles.isEmpty ? [d.composeFile] : d.container.configFiles
        let fileArgs = files.map { "-f \(Shell.quote($0))" }.joined(separator: " ")
        let project = d.project.isEmpty ? "" : "-p \(Shell.quote(d.project)) "
        return """
        if docker compose version >/dev/null 2>&1; then
          dc() { docker compose \(project)\(fileArgs) "$@"; }
        elif command -v docker-compose >/dev/null 2>&1; then
          dc() { docker-compose \(project)\(fileArgs) "$@"; }
        else
          echo "PA_ERROR=Weder 'docker compose' noch 'docker-compose' gefunden"; exit 20
        fi
        """
    }

    /// Backup, edit compose, pull (stack keeps running), stop, back up config consistently, start.
    public static func update(_ plan: UpdatePlan) -> String {
        let d = plan.deployment
        let file = Shell.quote(d.composeFile)
        var s = """
        set -eu
        cd -- \(Shell.quote(d.workingDir))
        \(composeFunction(d))
        echo "PA_STEP=backup"
        TS=$(date +%Y%m%d-%H%M%S)
        B="\(backupRoot)/$TS"
        mkdir -p "$B"
        cp -p -- \(file) "$B/"
        for f in .env config/config.yml config/traefik; do [ -e "$f" ] && cp -rp -- "$f" "$B/" 2>/dev/null || true; done
        restore_compose() { cp -p -- "$B/$(basename \(file))" \(file); }

        """
        if let pg = plan.postgresService {
            s += """
            if dc exec -T \(Shell.quote(pg)) sh -c 'pg_dumpall -U "${POSTGRES_USER:-postgres}"' > "$B/postgres.sql" 2>"$B/postgres.err"; then
              echo "Postgres-Sicherung: $B/postgres.sql"
            else
              echo "PA_WARN=Postgres-Sicherung fehlgeschlagen: $(head -c 300 "$B/postgres.err")"
            fi

            """
        }
        s += """
        echo "PA_BACKUP=$PWD/$B"

        """
        if !plan.retags.isEmpty {
            s += "echo \"PA_STEP=edit\"\n"
            for r in plan.retags {
                let line = r.lineNumber
                // Verify every line still holds the expected image before touching anything.
                s += """
                if ! sed -n '\(line)p' \(file) | grep -qF -- \(Shell.quote(r.oldReference)); then
                  echo "PA_ERROR=Zeile \(line) enthält nicht mehr \(r.oldReference.replacingOccurrences(of: "\"", with: "")) – Abbruch ohne Änderungen"; exit 21
                fi

                """
            }
            for r in plan.retags {
                let program = "\(r.lineNumber)s|\(sedPattern(r.oldReference))|\(sedReplacement(r.newReference))|"
                s += """
                sed -i.pa-bak \(Shell.quote(program)) \(file) && rm -f \(file).pa-bak
                sed -n '\(r.lineNumber)p' \(file) | grep -qF -- \(Shell.quote(r.newReference)) || { restore_compose; echo "PA_ERROR=Änderung an Zeile \(r.lineNumber) fehlgeschlagen – Original wiederhergestellt"; exit 22; }
                echo "  \(r.oldReference) → \(r.newReference)"

                """
            }
            s += """
            dc config -q || { restore_compose; echo "PA_ERROR=docker-compose.yml war nach der Änderung ungültig – Original wiederhergestellt"; exit 23; }

            """
        }
        s += """
        echo "PA_STEP=pull"
        if ! dc pull; then
          restore_compose
          echo "PA_ERROR=Images konnten nicht geladen werden – docker-compose.yml wiederhergestellt, Stack läuft unverändert weiter"; exit 24
        fi
        echo "PA_STEP=stop"
        dc stop
        echo "PA_STEP=snapshot"
        if [ -d config ]; then tar -czf "$B/config.tar.gz" config; fi
        echo "PA_STEP=up"
        dc up -d
        echo "PA_STEP=status"
        sleep 5
        dc ps
        echo "PA_STEP=done"
        """
        return s
    }

    /// Restores compose file and config from a backup and restarts the stack.
    public static func rollback(_ deployment: PangolinDeployment, backupPath: String) -> String {
        let file = Shell.quote(deployment.composeFile)
        let backup = Shell.quote(backupPath)
        return """
        set -eu
        cd -- \(Shell.quote(deployment.workingDir))
        \(composeFunction(deployment))
        [ -d \(backup) ] || { echo "PA_ERROR=Sicherung nicht gefunden: \(backupPath.replacingOccurrences(of: "\"", with: ""))"; exit 30; }
        echo "PA_STEP=stop"
        dc stop
        echo "PA_STEP=restore"
        cp -p -- \(backup)/"$(basename \(file))" \(file)
        if [ -f \(backup)/config.tar.gz ]; then tar -xzf \(backup)/config.tar.gz; fi
        if [ -f \(backup)/postgres.sql ]; then echo "PA_WARN=Postgres-Dump liegt unter \(backupPath.replacingOccurrences(of: "\"", with: ""))/postgres.sql – bei Bedarf manuell einspielen"; fi
        echo "PA_STEP=up"
        dc up -d
        sleep 3
        dc ps
        echo "PA_STEP=done"
        """
    }

    /// Runs `script` detached from the SSH session (survives the app going to the background)
    /// and streams its log until it finishes. Prints `PA_LOG=`, `PA_PID=` and finally `PA_EXIT=<code>`.
    public static func detached(_ script: String, access: DockerAccess) -> String {
        let job = "( \(script)\n) ; echo \"PA_EXIT=$?\""
        let runner = """
        LOG=$(mktemp /tmp/pangolin-admin-update.XXXXXX)
        if command -v setsid >/dev/null 2>&1; then DETACH="setsid"; else DETACH=""; fi
        nohup $DETACH sh -c \(Shell.quote(job)) > "$LOG" 2>&1 < /dev/null &
        PID=$!
        echo "PA_LOG=$LOG"
        echo "PA_PID=$PID"
        \(followScript(log: "$LOG", pid: "$PID", fromStart: true))
        """
        return access.wrap(runner)
    }

    /// Re-attaches to a running or finished detached job.
    public static func reattach(log: String, pid: Int, access: DockerAccess) -> String {
        access.wrap("""
        LOG=\(Shell.quote(log))
        PID=\(pid)
        [ -f "$LOG" ] || { echo "PA_ERROR=Log-Datei nicht mehr vorhanden"; exit 31; }
        \(followScript(log: "$LOG", pid: "$PID", fromStart: true))
        """)
    }

    /// Follows a log file until the process exits (portable, no GNU `tail --pid`).
    static func followScript(log: String, pid: String, fromStart: Bool) -> String {
        """
        tail -n +1 -f "\(log)" & T=$!
        while kill -0 "\(pid)" 2>/dev/null; do sleep 1; done
        sleep 1
        kill "$T" 2>/dev/null || true
        wait "$T" 2>/dev/null || true
        """
    }

    /// Escapes a literal for a sed basic regular expression with `|` as delimiter.
    static func sedPattern(_ literal: String) -> String {
        var out = ""
        for ch in literal {
            if "\\.*[]^$|".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Escapes a literal for the sed replacement part.
    static func sedReplacement(_ literal: String) -> String {
        var out = ""
        for ch in literal {
            if "\\|&".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}
