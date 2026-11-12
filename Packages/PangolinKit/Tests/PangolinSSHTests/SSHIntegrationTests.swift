import Foundation
import XCTest
@testable import PangolinSSH

/// Runs against a real OpenSSH server configured with `TrustedUserCAKeys`.
/// Set `PANGOLIN_SSH_TEST_DIR` to a directory containing the CA, host and user keys
/// (see scripts/ssh-test-server.sh); otherwise these tests are skipped.
final class SSHIntegrationTests: XCTestCase {
    var dir: URL!
    let server = SSHServer(host: "127.0.0.1", port: 2222, username: ProcessInfo.processInfo.environment["USER"] ?? "root")

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["PANGOLIN_SSH_TEST_DIR"] else {
            throw XCTSkip("PANGOLIN_SSH_TEST_DIR not set")
        }
        dir = URL(fileURLWithPath: path)
    }

    private func file(_ name: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    private func identity(_ name: String) throws -> SSHIdentity {
        try SSHIdentity.importOpenSSH(file(name)).withCertificate(file("\(name)-cert.pub"))
    }

    private func hostFingerprint() throws -> String {
        // Expected value printed by `ssh-keygen -lf host_ed25519.pub`, stored by the setup script.
        try file("host_fingerprint").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testEd25519CertificateLoginAndCommandOutput() async throws {
        let connection = try await SSHConnection.connect(to: server, identity: identity("user_ed"), hostKey: .trustOnFirstUse)
        XCTAssertEqual(connection.hostKeyFingerprint, try hostFingerprint())

        let result = try await connection.collect("echo hello; echo world; echo oops >&2; exit 3")
        XCTAssertEqual(result.stdout, "hello\nworld")
        XCTAssertEqual(result.stderr, "oops")
        XCTAssertEqual(result.exitCode, 3)

        // Several commands over one connection.
        let second = try await connection.collect("printf 'no-newline'")
        XCTAssertEqual(second.stdout, "no-newline")
        XCTAssertEqual(second.exitCode, 0)
        await connection.close()
    }

    func testStreamingDeliversLinesBeforeExit() async throws {
        let connection = try await SSHConnection.connect(to: server, identity: identity("user_ed"),
                                                         hostKey: .pinned(hostFingerprint()))
        var events: [SSHOutput] = []
        for try await event in connection.run("for i in 1 2 3; do echo line$i; sleep 0.2; done") {
            events.append(event)
        }
        XCTAssertEqual(events, [.stdout("line1"), .stdout("line2"), .stdout("line3"), .exit(0)])
        await connection.close()
    }

    func testECDSACertificateLogin() async throws {
        let connection = try await SSHConnection.connect(to: server, identity: identity("user_ec"),
                                                         hostKey: .pinned(hostFingerprint()))
        let result = try await connection.collect("whoami")
        XCTAssertEqual(result.stdout, server.username)
        await connection.close()
    }

    func testGeneratedKeySignedByCA() async throws {
        // Simulates the in-app flow: generate key, show public key, user signs it with the CA.
        let generated = try SSHIdentity.generate(useSecureEnclave: false)
        let pubPath = dir.appendingPathComponent("generated.pub")
        try (try generated.publicKeyLine(comment: "iphone")).write(to: pubPath, atomically: true, encoding: .utf8)
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        sign.arguments = ["-q", "-s", dir.appendingPathComponent("ca").path, "-I", "app", "-n", server.username, "-V", "-5m:+1h", pubPath.path]
        try sign.run()
        sign.waitUntilExit()
        XCTAssertEqual(sign.terminationStatus, 0)

        let cert = try file("generated-cert.pub")
        let identity = try generated.withCertificate(cert)
        let info = try SSHCertificateInfo(cert)
        XCTAssertEqual(info.principals, [server.username])
        XCTAssertEqual(info.keyID, "app")
        XCTAssertTrue(info.isValid())

        let connection = try await SSHConnection.connect(to: server, identity: identity, hostKey: .pinned(hostFingerprint()))
        let ok = try await connection.collect("echo ok")
        XCTAssertEqual(ok.stdout, "ok")
        await connection.close()

        // Round trip through the Keychain representation.
        let restored = try SSHIdentity(serialized: identity.serialized, certificate: identity.certificate)
        XCTAssertEqual(restored, identity)
    }

    /// Same structure as UpdateScript.detached: the job must survive and the channel must close cleanly.
    func testDetachedJobStreamsAndChannelCloses() async throws {
        let connection = try await SSHConnection.connect(to: server, identity: identity("user_ed"),
                                                         hostKey: .pinned(hostFingerprint()))
        let command = """
        LOG=$(mktemp /tmp/pa-test.XXXXXX)
        nohup setsid sh -c '( for i in 1 2 3; do echo step$i; sleep 0.3; done; exit 7 ) ; echo "PA_EXIT=$?"' > "$LOG" 2>&1 < /dev/null &
        PID=$!
        echo "PA_PID=$PID"
        tail -n +1 -f "$LOG" & T=$!
        while kill -0 "$PID" 2>/dev/null; do sleep 1; done
        sleep 1
        kill "$T" 2>/dev/null || true
        wait "$T" 2>/dev/null || true
        rm -f "$LOG"
        """
        let start = Date()
        let result = try await connection.collect(command)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "channel must not hang")
        let lines = result.stdout.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("step1") && lines.contains("step3"), result.stdout)
        XCTAssertTrue(lines.contains("PA_EXIT=7"), result.stdout)
        await connection.close()
    }

    func testWrongHostKeyIsRejected() async throws {
        do {
            _ = try await SSHConnection.connect(to: server, identity: identity("user_ed"),
                                                hostKey: .pinned("SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"))
            XCTFail("Expected host key mismatch")
        } catch let error as SSHError {
            guard case .hostKeyMismatch(_, let actual) = error else { return XCTFail("Wrong error \(error)") }
            XCTAssertEqual(actual, try hostFingerprint())
        }
    }

    func testCertificateForOtherPrincipalIsRejected() async throws {
        do {
            _ = try await SSHConnection.connect(to: server, identity: identity("user_wrongprincipal"),
                                                hostKey: .pinned(hostFingerprint()))
            XCTFail("Expected authentication failure")
        } catch let error as SSHError {
            XCTAssertEqual(error, .authenticationFailed)
        }
    }

    func testCertificateMustMatchKey() throws {
        let key = try SSHIdentity.importOpenSSH(file("user_ed"))
        XCTAssertThrowsError(try key.withCertificate(file("user_ec-cert.pub"))) { error in
            XCTAssertEqual(error as? SSHKeyError, .certificateDoesNotMatchKey)
        }
    }

    func testEncryptedKeyGivesHelpfulError() throws {
        XCTAssertThrowsError(try SSHIdentity.importOpenSSH(file("user_encrypted"))) { error in
            XCTAssertEqual(error as? SSHKeyError, .encryptedKey)
        }
    }

    func testPublicKeyLineMatchesOpenSSH() throws {
        let identity = try SSHIdentity.importOpenSSH(file("user_ed"))
        let expected = try file("user_ed.pub").split(separator: " ").prefix(2).joined(separator: " ")
        XCTAssertEqual(try identity.publicKeyLine(comment: "x").split(separator: " ").prefix(2).joined(separator: " "), expected)
    }

    func testConnectionRefused() async throws {
        let closed = SSHServer(host: "127.0.0.1", port: 1, username: "root")
        do {
            _ = try await SSHConnection.connect(to: closed, identity: identity("user_ed"), hostKey: .trustOnFirstUse, timeout: 3)
            XCTFail("Expected failure")
        } catch let error as SSHError {
            guard case .connectionFailed = error else { return XCTFail("Wrong error \(error)") }
        }
    }
}
