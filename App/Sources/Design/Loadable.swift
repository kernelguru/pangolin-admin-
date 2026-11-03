import SwiftUI

/// Simple loading state for screens.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

/// Wraps a destructive or mutating API call with a busy flag and error alert.
@MainActor
@Observable
final class ActionRunner {
    var isRunning = false
    var errorMessage: String?
    var successMessage: String?

    var showsError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    /// Runs `operation`; returns `true` on success.
    @discardableResult
    func run(success: String? = nil, _ operation: () async throws -> Void) async -> Bool {
        isRunning = true
        successMessage = nil
        defer { isRunning = false }
        do {
            try await operation()
            successMessage = success
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

extension View {
    /// Shows the runner's error as an alert.
    func actionErrors(_ runner: ActionRunner) -> some View {
        modifier(ActionErrorModifier(runner: runner))
    }
}

private struct ActionErrorModifier: ViewModifier {
    @Bindable var runner: ActionRunner

    func body(content: Content) -> some View {
        content
            .alert("Aktion fehlgeschlagen", isPresented: $runner.showsError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(runner.errorMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: runner.successMessage)
            .overlay {
                if runner.isRunning {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            }
    }
}
