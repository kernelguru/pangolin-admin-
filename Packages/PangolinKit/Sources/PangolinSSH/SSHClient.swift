import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// Connection target.
public struct SSHServer: Sendable, Equatable, Codable {
    public var host: String
    public var port: Int
    public var username: String

    public init(host: String, port: Int = 22, username: String) {
        self.host = host
        self.port = port
        self.username = username
    }
}

/// How the server's host key is verified.
public enum SSHHostKeyPolicy: Sendable, Equatable {
    /// Only accept this `SHA256:…` fingerprint.
    case pinned(String)
    /// Accept any key (first connection); the fingerprint is reported so the user can confirm and pin it.
    case trustOnFirstUse
}

public enum SSHError: Error, Sendable, Equatable, LocalizedError {
    case connectionFailed(String)
    case hostKeyMismatch(expected: String, actual: String)
    case authenticationFailed
    case channelFailed(String)
    case commandFailed(exitCode: Int, output: String)
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let detail):
            "SSH-Verbindung fehlgeschlagen: \(detail)"
        case .hostKeyMismatch(let expected, let actual):
            "WARNUNG: Der Host-Schlüssel des Servers hat sich geändert!\nErwartet: \(expected)\nErhalten: \(actual)\nDas kann eine Neuinstallation sein – oder ein Angriff. Verbindung abgebrochen."
        case .authenticationFailed:
            "SSH-Anmeldung abgelehnt. Prüfe Benutzername, ob das Zertifikat gültig ist (Principal = Benutzername, Laufzeit) und ob der Server der CA vertraut (TrustedUserCAKeys)."
        case .channelFailed(let detail):
            "SSH-Kanal fehlgeschlagen: \(detail)"
        case .commandFailed(let code, let output):
            "Befehl fehlgeschlagen (Exit-Code \(code)).\n\(output)"
        case .disconnected:
            "Die SSH-Verbindung wurde getrennt."
        }
    }
}

/// One piece of command output.
public enum SSHOutput: Sendable, Equatable {
    case stdout(String)
    case stderr(String)
    /// Final event: the command's exit status (nil if the server sent none).
    case exit(Int?)
}

/// Collected result of a command.
public struct SSHCommandResult: Sendable, Equatable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int?

    public var succeeded: Bool { exitCode == 0 }
    public var combinedOutput: String { [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n") }
}

/// An authenticated SSH connection that can run commands.
public final class SSHConnection: Sendable {
    public let hostKeyFingerprint: String
    private let group: MultiThreadedEventLoopGroup
    private let channel: Channel

    private init(group: MultiThreadedEventLoopGroup, channel: Channel, hostKeyFingerprint: String) {
        self.group = group
        self.channel = channel
        self.hostKeyFingerprint = hostKeyFingerprint
    }

    /// Connects, verifies the host key and authenticates with the identity (certificate if present).
    public static func connect(to server: SSHServer, identity: SSHIdentity, hostKey: SSHHostKeyPolicy,
                               timeout: TimeInterval = 15) async throws -> SSHConnection {
        let privateKey = try identity.makePrivateKey()
        let certified = try identity.certifiedKey()
        let hostKeyBox = HostKeyBox()
        let errors = ErrorBox()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.milliseconds(Int64(timeout * 1000)))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let userAuth = CertificateAuthDelegate(username: server.username, privateKey: privateKey,
                                                           certifiedKey: certified, errors: errors)
                    let hostAuth = HostKeyDelegate(policy: hostKey, box: hostKeyBox, errors: errors)
                    let handler = NIOSSHHandler(
                        role: .client(.init(userAuthDelegate: userAuth, serverAuthDelegate: hostAuth)),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                    try channel.pipeline.syncOperations.addHandler(handler)
                    try channel.pipeline.syncOperations.addHandler(ErrorCaptureHandler(errors: errors))
                }
            }

        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: server.host, port: server.port).get()
        } catch {
            try? await group.shutdownGracefully()
            throw SSHError.connectionFailed(describe(error))
        }

        let connection = SSHConnection(group: group, channel: channel, hostKeyFingerprint: "")
        // Opening a session channel waits for key exchange and user authentication to finish,
        // so a successful no-op proves the connection is usable.
        do {
            let probe = try await connection.collect("true", fingerprint: hostKeyBox.value ?? "")
            _ = probe
        } catch {
            await connection.closeSilently()
            throw errors.first ?? (error as? SSHError) ?? SSHError.connectionFailed(describe(error))
        }
        return SSHConnection(group: group, channel: channel, hostKeyFingerprint: hostKeyBox.value ?? "")
    }

    /// Runs a command and streams its output line by line.
    public func run(_ command: String) -> AsyncThrowingStream<SSHOutput, Error> {
        AsyncThrowingStream { continuation in
            let channel = self.channel
            channel.eventLoop.execute {
                do {
                    let handler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                    let promise = channel.eventLoop.makePromise(of: Channel.self)
                    handler.createChannel(promise) { child, type in
                        guard type == .session else {
                            return child.eventLoop.makeFailedFuture(SSHError.channelFailed("Unerwarteter Kanaltyp"))
                        }
                        return child.eventLoop.makeCompletedFuture {
                            try child.pipeline.syncOperations.addHandler(
                                ExecHandler(command: command, continuation: continuation))
                        }
                    }
                    promise.futureResult.whenFailure { error in
                        continuation.finish(throwing: (error as? SSHError) ?? SSHError.channelFailed(describe(error)))
                    }
                } catch {
                    continuation.finish(throwing: SSHError.disconnected)
                }
            }
        }
    }

    /// Runs a command and collects all output.
    public func collect(_ command: String) async throws -> SSHCommandResult {
        try await collect(command, fingerprint: hostKeyFingerprint)
    }

    private func collect(_ command: String, fingerprint: String) async throws -> SSHCommandResult {
        var result = SSHCommandResult(stdout: "", stderr: "", exitCode: nil)
        var out: [String] = []
        var err: [String] = []
        for try await event in run(command) {
            switch event {
            case .stdout(let line): out.append(line)
            case .stderr(let line): err.append(line)
            case .exit(let code): result.exitCode = code
            }
        }
        result.stdout = out.joined(separator: "\n")
        result.stderr = err.joined(separator: "\n")
        return result
    }

    public func close() async {
        await closeSilently()
    }

    private func closeSilently() async {
        try? await channel.close().get()
        try? await group.shutdownGracefully()
    }
}

func describe(_ error: Error) -> String {
    if let error = error as? LocalizedError, let text = error.errorDescription { return text }
    if let error = error as? IOError { return error.description }
    return String(describing: error)
}

// MARK: - Delegates

/// Thread-safe holder for the first pipeline error.
final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?

    var first: Error? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func record(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        if stored == nil { stored = error }
    }
}

final class HostKeyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var value: String? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func set(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        stored = value
    }
}

final class HostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let policy: SSHHostKeyPolicy
    let box: HostKeyBox
    let errors: ErrorBox

    init(policy: SSHHostKeyPolicy, box: HostKeyBox, errors: ErrorBox) {
        self.policy = policy
        self.box = box
        self.errors = errors
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        guard let fingerprint = try? SSHFingerprint.sha256(of: hostKey) else {
            let error = SSHError.connectionFailed("Host-Schlüssel nicht lesbar")
            errors.record(error)
            validationCompletePromise.fail(error)
            return
        }
        box.set(fingerprint)
        switch policy {
        case .trustOnFirstUse:
            validationCompletePromise.succeed(())
        case .pinned(let expected):
            if expected == fingerprint {
                validationCompletePromise.succeed(())
            } else {
                let error = SSHError.hostKeyMismatch(expected: expected, actual: fingerprint)
                errors.record(error)
                validationCompletePromise.fail(error)
            }
        }
    }
}

final class CertificateAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    let username: String
    let privateKey: NIOSSHPrivateKey
    let certifiedKey: NIOSSHCertifiedPublicKey?
    let errors: ErrorBox
    private var attempts = 0

    init(username: String, privateKey: NIOSSHPrivateKey, certifiedKey: NIOSSHCertifiedPublicKey?, errors: ErrorBox) {
        self.username = username
        self.privateKey = privateKey
        self.certifiedKey = certifiedKey
        self.errors = errors
    }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        attempts += 1
        // Offer the certificate first, then the plain key (for authorized_keys setups).
        let offer: NIOSSHUserAuthenticationOffer.Offer.PrivateKey?
        switch (attempts, certifiedKey) {
        case (1, .some(let cert)): offer = .init(privateKey: privateKey, certifiedKey: cert)
        case (1, .none), (2, .some): offer = .init(privateKey: privateKey)
        default: offer = nil
        }
        guard availableMethods.contains(.publicKey), let offer else {
            errors.record(SSHError.authenticationFailed)
            nextChallengePromise.fail(SSHError.authenticationFailed)
            return
        }
        nextChallengePromise.succeed(.init(username: username, serviceName: "", offer: .privateKey(offer)))
    }
}

final class ErrorCaptureHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any
    let errors: ErrorBox

    init(errors: ErrorBox) { self.errors = errors }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        errors.record(error)
        context.close(promise: nil)
    }
}

// MARK: - Exec channel

/// Sends an exec request and forwards stdout/stderr lines and the exit status to a stream.
final class ExecHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData

    private let command: String
    private let continuation: AsyncThrowingStream<SSHOutput, Error>.Continuation
    private var stdoutBuffer: [UInt8] = []
    private var stderrBuffer: [UInt8] = []
    private var exitCode: Int?
    private var finished = false

    init(command: String, continuation: AsyncThrowingStream<SSHOutput, Error>.Continuation) {
        self.command = command
        self.continuation = continuation
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { [continuation] error in
            continuation.finish(throwing: SSHError.channelFailed(describe(error)))
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        let request = SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)
        context.triggerUserOutboundEvent(request, promise: nil)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard case .byteBuffer(var bytes) = message.data,
              let chunk = bytes.readBytes(length: bytes.readableBytes) else { return }
        switch message.type {
        case .channel:
            stdoutBuffer += chunk
            emitLines(from: &stdoutBuffer, stderr: false)
        case .stdErr:
            stderrBuffer += chunk
            emitLines(from: &stderrBuffer, stderr: true)
        default:
            break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let status as SSHChannelRequestEvent.ExitStatus:
            exitCode = status.exitStatus
        case is ChannelFailureEvent:
            finish(error: SSHError.channelFailed("Server hat den Befehl abgelehnt"))
            context.close(promise: nil)
        case let event as ChannelEvent where event == .inputClosed:
            context.close(promise: nil)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        finish(error: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        finish(error: SSHError.channelFailed(describe(error)))
        context.close(promise: nil)
    }

    private func emitLines(from buffer: inout [UInt8], stderr: Bool) {
        while let index = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[..<index], as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            buffer.removeSubrange(...index)
            continuation.yield(stderr ? .stderr(line) : .stdout(line))
        }
    }

    private func finish(error: Error?) {
        guard !finished else { return }
        finished = true
        if !stdoutBuffer.isEmpty { continuation.yield(.stdout(String(decoding: stdoutBuffer, as: UTF8.self))) }
        if !stderrBuffer.isEmpty { continuation.yield(.stderr(String(decoding: stderrBuffer, as: UTF8.self))) }
        stdoutBuffer = []
        stderrBuffer = []
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.yield(.exit(exitCode))
            continuation.finish()
        }
    }
}
