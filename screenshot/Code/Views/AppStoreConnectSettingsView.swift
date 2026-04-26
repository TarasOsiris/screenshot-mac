import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

struct AppStoreConnectSettingsView: View {
    private static let apiKeysURL = URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!
    private static let docsURL = URL(string: "https://developer.apple.com/documentation/appstoreconnectapi")!

    @State private var credentials = AppStoreConnectCredentialsStore.shared
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var fileImporterPresented = false
    @State private var importError: String?
    @State private var showClearConfirmation = false

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    private struct SetupItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let isComplete: Bool
    }

    var body: some View {
        Form {
            statusSection
            credentialsSection
            helpSection
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: Self.p8ContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .confirmationDialog(
            "Clear App Store Connect credentials?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Credentials", role: .destructive) {
                clearCredentials()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the Issuer ID, Key ID, and imported private key from this Mac.")
        }
        .onAppear { credentials.refreshPrivateKeyPresence() }
        .onChange(of: credentials.issuerId) { _, _ in resetConnectionState() }
        .onChange(of: credentials.keyId) { _, _ in resetConnectionState() }
        .onChange(of: credentials.hasPrivateKey) { _, _ in resetConnectionState() }
    }

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
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
                    Text(setupSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(setupItems) { item in
                        setupItemRow(item)
                    }
                }

                if let testResult {
                    connectionFeedbackRow(result: testResult)
                }
            }
        } header: {
            Text("Setup")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Values are saved automatically on this Mac. The private key is stored in Keychain.")
                Text("Testing lists one app from the account. If this passes but uploads fail, check that the API key can edit the specific app and version.")
            }
                .foregroundStyle(.secondary)
        }
    }

    private var credentialsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Issuer ID",
                          text: normalizedIssuerIdBinding,
                          prompt: Text("e.g. 57246542-96fe-1a63-e053-0824d011072a"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .textContentType(.oneTimeCode)

                fieldStatus(
                    value: trimmedIssuerId,
                    isComplete: isIssuerIdValid,
                    emptyMessage: String(localized: "Paste the Issuer ID from the API Keys page."),
                    invalidMessage: String(localized: "Issuer ID should be a UUID.")
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Key ID",
                          text: normalizedKeyIdBinding,
                          prompt: Text("10-character key ID"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .textContentType(.oneTimeCode)

                fieldStatus(
                    value: trimmedKeyId,
                    isComplete: isKeyIdValid,
                    emptyMessage: String(localized: "Paste the 10-character Key ID."),
                    invalidMessage: String(localized: "Key ID is usually 10 uppercase letters and numbers.")
                )
            }

            LabeledContent("Private Key (.p8)") {
                HStack(spacing: 6) {
                    if credentials.hasPrivateKey {
                        Label("Imported", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Button("Replace…") { fileImporterPresented = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Remove") {
                            credentials.deletePrivateKey()
                            testResult = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Import .p8 File…") { fileImporterPresented = true }
                            .buttonStyle(.bordered)
                    }
                }
            }

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if credentials.hasPrivateKey {
                Text("Private key imported. App Store Connect lets you download a .p8 key only once, so keep the original file somewhere safe.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if credentials.isConfigured || credentials.hasPrivateKey {
                HStack {
                    Spacer()
                    Button("Clear Credentials…", role: .destructive) {
                        showClearConfirmation = true
                    }
                    .controlSize(.small)
                }
            }
        } header: {
            Text("API Key")
        } footer: {
            Text("Use an App Store Connect API key with access to edit app metadata. Account Holder, Admin, or App Manager roles are typical for screenshot uploads.")
                .foregroundStyle(.secondary)
        }
    }

    private var helpSection: some View {
        Section("Actions") {
            Link("Open API Keys", destination: Self.apiKeysURL)
            Link("Create or manage API keys", destination: Self.apiKeysURL)
            Link("App Store Connect API documentation", destination: Self.docsURL)
        }
    }

    private var statusMessage: String {
        if connectionTestPassed {
            return String(localized: "The API key is connected and ready for screenshot uploads.")
        }
        if credentials.isConfigured {
            return String(localized: "Run the connection test once before uploading screenshots.")
        }
        return String(localized: "Complete the API key details below, then test the connection from the checklist.")
    }

    private var setupItems: [SetupItem] {
        [
            SetupItem(
                id: "issuer",
                title: String(localized: "Issuer ID"),
                detail: isIssuerIdValid ? trimmedIssuerId : String(localized: "Required UUID from App Store Connect"),
                isComplete: isIssuerIdValid
            ),
            SetupItem(
                id: "key",
                title: String(localized: "Key ID"),
                detail: isKeyIdValid ? trimmedKeyId : String(localized: "Required 10-character key ID"),
                isComplete: isKeyIdValid
            ),
            SetupItem(
                id: "private-key",
                title: String(localized: "Private key"),
                detail: credentials.hasPrivateKey ? String(localized: ".p8 key imported") : String(localized: "Import the .p8 file downloaded when the key was created"),
                isComplete: credentials.hasPrivateKey
            ),
            SetupItem(
                id: "connection",
                title: String(localized: "Connection"),
                detail: connectionDetail,
                isComplete: connectionTestPassed
            )
        ]
    }

    private var connectionDetail: String {
        switch testResult {
        case .success:
            return String(localized: "Last test passed")
        case .failure:
            return String(localized: "Last test failed")
        case nil:
            return credentials.isConfigured ? String(localized: "Ready to test") : String(localized: "Complete the first three items to enable testing")
        }
    }

    private var connectionTestPassed: Bool {
        if case .success = testResult { return true }
        return false
    }

    private var canTestConnection: Bool {
        credentials.isConfigured && !isTesting
    }

    private var statusTitle: String {
        if connectionTestPassed {
            return String(localized: "Connected")
        }
        return credentials.isConfigured ? String(localized: "Ready to test") : String(localized: "Finish setup")
    }

    private var statusSymbolName: String {
        if connectionTestPassed {
            return "checkmark.seal.fill"
        }
        return credentials.isConfigured ? "bolt.horizontal.circle.fill" : "key.horizontal"
    }

    private var statusSymbolColor: Color {
        if connectionTestPassed {
            return .green
        }
        return credentials.isConfigured ? .orange : .secondary
    }

    private var setupSummary: String {
        String(localized: "\(setupItems.filter(\.isComplete).count) of \(setupItems.count) complete")
    }

    private var missingConfigurationMessage: String {
        let missing = setupItems
            .filter { $0.id != "connection" && !$0.isComplete }
            .map(\.title)
        guard !missing.isEmpty else { return String(localized: "Configuration is complete.") }
        return String(localized: "Missing: \(missing.joined(separator: ", ")).")
    }

    private var trimmedIssuerId: String {
        credentials.trimmedIssuerId
    }

    private var trimmedKeyId: String {
        credentials.trimmedKeyId
    }

    private var isIssuerIdValid: Bool {
        credentials.isIssuerIdValid
    }

    private var isKeyIdValid: Bool {
        credentials.isKeyIdValid
    }

    private var normalizedIssuerIdBinding: Binding<String> {
        Binding(
            get: { credentials.issuerId },
            set: { credentials.issuerId = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private var normalizedKeyIdBinding: Binding<String> {
        Binding(
            get: { credentials.keyId },
            set: { credentials.keyId = $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        )
    }

    private func setupItemRow(_ item: SetupItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : item.id == "connection" ? "bolt.horizontal.circle" : "circle")
                .foregroundStyle(item.isComplete ? .green : .secondary)
                .font(.headline)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if item.id == "connection" {
                Button {
                    Task { await runTest() }
                } label: {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isTesting ? "Testing…" : "Test")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canTestConnection)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func fieldStatus(value: String, isComplete: Bool, emptyMessage: String, invalidMessage: String) -> some View {
        if isComplete {
            Label("Looks valid", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else {
            Text(value.isEmpty ? emptyMessage : invalidMessage)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private static let p8ContentTypes: [UTType] = [
        UTType(filenameExtension: "p8") ?? .data,
        .plainText,
        .data
    ]

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let pem = try String(contentsOf: url, encoding: .utf8)
            do {
                _ = try P256.Signing.PrivateKey(pemRepresentation: pem)
            } catch {
                importError = String(localized: "That doesn't look like a valid .p8 private key.")
                return
            }
            try credentials.savePrivateKey(pem)
            testResult = nil
        } catch {
            importError = String(localized: "Could not import the private key: \(error.localizedDescription)")
        }
    }

    private func runTest() async {
        credentials.refreshPrivateKeyPresence()
        resetConnectionState(clearImportError: false)
        isTesting = true
        defer { isTesting = false }
        do {
            let message = try await AppStoreConnectAPIService.shared.testConnection()
            testResult = .success(message)
        } catch {
            testResult = .failure(connectionFailureMessage(for: error))
        }
    }

    private func resetConnectionState(clearImportError: Bool = true) {
        testResult = nil
        if clearImportError {
            importError = nil
        }
    }

    private func clearCredentials() {
        credentials.issuerId = ""
        credentials.keyId = ""
        credentials.deletePrivateKey()
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

    private func connectionFailureMessage(for error: Error) -> String {
        if let apiError = error as? AppStoreConnectAPIError {
            switch apiError {
            case .httpError(let status, let message) where status == 401 || status == 403:
                return String(localized: "\(message) Check that the Issuer ID, Key ID, private key, and API key permissions match the App Store Connect key.")
            case .httpError(let status, let message):
                return String(localized: "App Store Connect returned \(status): \(message)")
            case .transport(let transportError):
                return String(localized: "Network request failed: \(transportError.localizedDescription)")
            default:
                return apiError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

#Preview {
    AppStoreConnectSettingsView()
        .frame(width: 520, height: 560)
}
