import SwiftUI
import UniformTypeIdentifiers

struct GooglePlaySettingsView: View {
    private static let consoleURL = URL(string: "https://play.google.com/console/")!
    private static let docsURL = URL(string: "https://developers.google.com/android-publisher/authorization")!

    @State private var credentials = GooglePlayCredentialsStore.shared
    @State private var isTesting = false
    @State private var testResult: StoreConnectionTestResult?
    @State private var fileImporterPresented = false
    @State private var importError: String?
    @State private var showClearConfirmation = false

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
        .storeCredentialsRemovalConfirmation(
            title: "Remove Google Play credentials?",
            message: "This removes the imported service account key from this device.",
            confirmLabel: "Remove",
            isPresented: $showClearConfirmation,
            onRemove: clearCredentials
        )
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

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            StoreConnectionTestButton(isTesting: isTesting, isEnabled: canTestConnection) {
                await runTest()
            }

            if let testResult {
                StoreConnectionFeedbackRow(result: testResult)
            }

            if credentials.hasServiceAccount {
                StoreRemoveCredentialsButton(label: "Remove Credentials…", isConfirming: $showClearConfirmation)
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
        StoreCredentialsStatusHeader(status: status, message: statusMessage)
    }

    private var helpSection: some View {
        Section("Actions") {
            Link("Open Play Console", destination: Self.consoleURL)
            Link("Authorization documentation", destination: Self.docsURL)
        }
    }

    private var demoModeSection: some View {
        StoreDemoModeSection(
            isDemoMode: Binding(
                get: { credentials.isDemoMode },
                set: { credentials.isDemoMode = $0; testResult = nil }
            ),
            sectionTitle: "Demo Mode",
            toggleDescription: "Run a simulated upload — no service account required and no traffic is sent to Google Play.",
            activeNote: "Demo mode is active. The service account above is ignored until you turn demo mode off.",
            footer: "Use demo mode to walk through the Google Play upload feature without a service account."
        )
    }

    // MARK: - Status

    private var status: StoreCredentialsStatus {
        .resolve(
            isDemoMode: credentials.isDemoMode,
            connectionTestPassed: testResult?.passed == true,
            hasCredentials: credentials.hasServiceAccount
        )
    }

    private var statusMessage: String {
        switch status {
        case .demoMode:
            return String(localized: "Demo mode is on. The upload wizard never contacts Google Play.")
        case .connected:
            return String(localized: "The service account is connected and ready for screenshot uploads.")
        case .readyToTest:
            return String(localized: "Run the connection test once before uploading screenshots.")
        case .finishSetup:
            return String(localized: "Import the service account JSON key below, then test the connection.")
        }
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

}
