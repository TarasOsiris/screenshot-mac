#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

struct GooglePlaySettingsView: View {
    private static let consoleURL = URL(string: "https://play.google.com/console/")!
    private static let docsURL = URL(string: "https://developers.google.com/android-publisher/authorization")!

    @State private var credentials = GooglePlayCredentialsStore.shared
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var fileImporterPresented = false
    @State private var pasteText = ""
    @State private var importError: String?
    @State private var showClearConfirmation = false

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            credentialsSection
            helpSection
            demoModeSection
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: [.json, .plainText, .data],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        #if os(macOS)
        .confirmationDialog(
            "Remove Google Play credentials?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { clearCredentials() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the imported service account key from this Mac.")
        }
        #else
        .alert("Remove Google Play credentials?", isPresented: $showClearConfirmation) {
            Button("Remove", role: .destructive) { clearCredentials() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the imported service account key from this device.")
        }
        #endif
    }

    private var credentialsSection: some View {
        Section {
            statusHeader

            if let email = credentials.clientEmail {
                LabeledContent("Service account") {
                    Text(email)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Service account key (.json)")
                    .font(.callout)
                HStack(spacing: 8) {
                    Button(credentials.hasServiceAccount ? "Replace…" : "Import .json File…") {
                        fileImporterPresented = true
                    }
                    .buttonStyle(.bordered)
                    if credentials.hasServiceAccount {
                        Label("Imported", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }

            DisclosureGroup("Or paste JSON") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $pasteText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    HStack {
                        Spacer()
                        Button("Save Pasted Key") { savePasted() }
                            .buttonStyle(.bordered)
                            .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            #if os(macOS)
            HStack {
                Spacer()
                Button {
                    Task { await runTest() }
                } label: {
                    HStack(spacing: 6) {
                        if isTesting { ProgressView().controlSize(.small) }
                        Text(isTesting ? "Testing…" : "Test Connection")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canTestConnection)
            }
            #else
            Button {
                Task { await runTest() }
            } label: {
                HStack(spacing: 6) {
                    if isTesting { ProgressView().controlSize(.small) }
                    Text(isTesting ? "Testing…" : "Test Connection")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canTestConnection)
            #endif

            if let testResult {
                connectionFeedbackRow(result: testResult)
            }

            if credentials.hasServiceAccount {
                #if os(macOS)
                HStack {
                    Spacer()
                    Button("Remove Credentials…", role: .destructive) { showClearConfirmation = true }
                        .controlSize(.small)
                }
                #else
                Button("Remove Credentials…", role: .destructive) { showClearConfirmation = true }
                    .frame(maxWidth: .infinity)
                #endif
            }
        } header: {
            Text("Service Account")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Create a service account in the Google Cloud console, enable the Google Play Android Developer API, and download its JSON key. In the Play Console, invite the service account under Users and permissions and grant it access to edit store listings.")
                Text("The key is stored in this device's Keychain.")
            }
            .foregroundStyle(.secondary)
        }
    }

    private var statusHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSymbolName)
                .foregroundStyle(statusSymbolColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.headline)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var helpSection: some View {
        Section("Actions") {
            Link("Open Play Console", destination: Self.consoleURL)
            Link("Authorization documentation", destination: Self.docsURL)
        }
    }

    private var demoModeSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { credentials.isDemoMode },
                set: { credentials.isDemoMode = $0; testResult = nil }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable demo mode")
                        .fontWeight(.medium)
                    Text("Run a simulated upload — no service account required and no traffic is sent to Google Play.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)

            if credentials.isDemoMode {
                Label("Demo mode is active. The service account above is ignored until you turn demo mode off.",
                      systemImage: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Demo Mode")
        } footer: {
            Text("Use demo mode to walk through the Google Play upload feature without a service account.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status

    private enum StatusState { case demoMode, connected, ready, finishSetup }

    private var statusState: StatusState {
        if credentials.isDemoMode { return .demoMode }
        if connectionTestPassed { return .connected }
        return credentials.hasServiceAccount ? .ready : .finishSetup
    }

    private var statusTitle: String {
        switch statusState {
        case .demoMode: return String(localized: "Demo mode")
        case .connected: return String(localized: "Connected")
        case .ready: return String(localized: "Ready to test")
        case .finishSetup: return String(localized: "Finish setup")
        }
    }

    private var statusMessage: String {
        switch statusState {
        case .demoMode:
            return String(localized: "Demo mode is on. The upload wizard never contacts Google Play.")
        case .connected:
            return String(localized: "The service account is connected and ready for screenshot uploads.")
        case .ready:
            return String(localized: "Run the connection test once before uploading screenshots.")
        case .finishSetup:
            return String(localized: "Import the service account JSON key below, then test the connection.")
        }
    }

    private var statusSymbolName: String {
        switch statusState {
        case .demoMode: return "theatermasks.fill"
        case .connected: return "checkmark.seal.fill"
        case .ready: return "bolt.horizontal.circle.fill"
        case .finishSetup: return "key.horizontal"
        }
    }

    private var statusSymbolColor: Color {
        switch statusState {
        case .demoMode: return .blue
        case .connected: return .green
        case .ready: return .orange
        case .finishSetup: return .secondary
        }
    }

    private var connectionTestPassed: Bool {
        if case .success = testResult { return true }
        return false
    }

    private var canTestConnection: Bool {
        credentials.isConfigured && !isTesting
    }

    // MARK: - Actions

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let json = try String(contentsOf: url, encoding: .utf8)
            try save(json: json)
        } catch let error as GooglePlayCredentialsError {
            importError = error.localizedDescription
        } catch {
            importError = String(localized: "Could not import the key: \(error.localizedDescription)")
        }
    }

    private func savePasted() {
        importError = nil
        do {
            try save(json: pasteText)
            pasteText = ""
        } catch let error as GooglePlayCredentialsError {
            importError = error.localizedDescription
        } catch {
            importError = error.localizedDescription
        }
    }

    private func save(json: String) throws {
        try credentials.saveServiceAccount(json: json)
        testResult = nil
    }

    private func runTest() async {
        testResult = nil
        isTesting = true
        defer { isTesting = false }
        do {
            let message = try await GooglePlayAPIService.shared.testConnection()
            testResult = .success(message)
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    private func clearCredentials() {
        credentials.deleteServiceAccount()
        testResult = nil
        importError = nil
    }

    @ViewBuilder
    private func connectionFeedbackRow(result: TestResult) -> some View {
        switch result {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
#endif
