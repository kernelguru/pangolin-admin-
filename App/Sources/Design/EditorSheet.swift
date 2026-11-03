import SwiftUI

/// Native form in a sheet (iOS 26 renders sheets as glass) with Cancel/Save toolbar.
/// `save` runs asynchronously; the sheet closes when it succeeds.
struct EditorSheet<Content: View>: View {
    let title: String
    var saveTitle: String = "Sichern"
    var canSave: Bool = true
    let save: @MainActor () async throws -> Void
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss
    @State private var runner = ActionRunner()

    var body: some View {
        Form {
            content
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(saveTitle) {
                    Task {
                        if await runner.run(success: title, save) { dismiss() }
                    }
                }
                .disabled(!canSave || runner.isRunning)
            }
        }
        .interactiveDismissDisabled(runner.isRunning)
        .actionErrors(runner)
    }
}

/// Text field for integers (ports, intervals) bound to an optional Int.
struct IntField: View {
    let title: String
    @Binding var value: Int?
    var prompt: String = ""

    var body: some View {
        LabeledContent(title) {
            TextField(prompt, text: Binding(
                get: { value.map(String.init) ?? "" },
                set: { value = Int($0.filter(\.isNumber)) }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
        }
    }
}

/// Small helper to present a sheet for an optional identifiable item with its own NavigationStack.
extension View {
    func editorSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>,
                                                      onDismiss: (() -> Void)? = nil,
                                                      @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in
            NavigationStack { content(value) }
        }
    }
}
