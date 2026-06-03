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
        VStack(alignment: .leading, spacing: 16) {
            #if os(macOS)
            Text(prompt.title)
                .font(.headline)
            #endif

            ProjectNameTextField(
                text: $text,
                placeholder: String(localized: "Project name"),
                onSubmit: confirm
            )
            .frame(height: 22)

            #if os(macOS)
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
            #endif
        }
        .padding(20)
        .frame(width: 360)
        .iosSheetChrome(
            Text(verbatim: prompt.title),
            confirmTitle: Text(verbatim: prompt.confirmTitle),
            confirmDisabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            showsCancel: true,
            onConfirm: confirm
        )
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
