#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

struct ProjectNamePrompt: Identifiable {
    let id = UUID()
    let title: String
    let confirmTitle: String
    let initialValue: String
    let onConfirm: (String) -> Void
}

struct ProjectNameSheet: View {
    let prompt: ProjectNamePrompt

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(prompt: ProjectNamePrompt) {
        self.prompt = prompt
        _text = State(initialValue: prompt.initialValue)
    }

    var body: some View {
        content
            .iosSheetChrome(
                Text(verbatim: prompt.title),
                confirmTitle: Text(verbatim: prompt.confirmTitle),
                confirmDisabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                showsCancel: true,
                detents: [.height(140)],
                onConfirm: confirm
            )
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt.title)
                .font(.headline)

            ProjectNameTextField(
                text: $text,
                placeholder: String(localized: "Project name"),
                onSubmit: confirm
            )
            .frame(height: 22)

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(prompt.confirmTitle) {
                    confirm()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        #else
        VStack(alignment: .leading, spacing: 0) {
            ProjectNameTextField(
                text: $text,
                placeholder: String(localized: "Project name"),
                onSubmit: confirm
            )
            Spacer(minLength: 0)
        }
        .padding(20)
        #endif
    }

    private func confirm() {
        prompt.onConfirm(String(text.prefix(100)))
        dismiss()
    }
}

#if os(iOS)
private struct ProjectNameTextField: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .submitLabel(.done)
            .onSubmit(onSubmit)
            .onAppear { focused = true }
    }
}
#else
private struct ProjectNameTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submit)

        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
            textField.selectText(nil)
        }

        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }

        @objc func submit() {
            onSubmit()
        }
    }
}
#endif
