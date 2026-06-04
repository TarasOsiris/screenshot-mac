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

    var body: some View {
        Form {
            credentialsSection
            helpSection
            demoModeSection
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: Self.p8ContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        #if os(macOS)
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
        #else
        // iPad: a centered alert, not an action-sheet popover anchored to the button.
        .alert("Clear App Store Connect credentials?", isPresented: $showClearConfirmation) {
            Button("Clear Credentials", role: .destructive) {
                clearCredentials()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the Issuer ID, Key ID, and imported private key from this Mac.")
        }
        #endif
        .onAppear { credentials.refreshPrivateKeyPresence() }
        .onChange(of: credentials.issuerId) { _, _ in resetConnectionState() }
        .onChange(of: credentials.keyId) { _, _ in resetConnectionState() }
        .onChange(of: credentials.hasPrivateKey) { _, _ in resetConnectionState() }
    }

    private var credentialsSection: some View {
        Section {
            statusHeader

            VStack(alignment: .leading, spacing: 4) {
                TextField("Issuer ID",
                          text: normalizedIssuerIdBinding,
                          prompt: Text("e.g. 57246542-96fe-1a63-e053-0824d011072a"))
                    .ascCredentialFieldStyle()

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
                    .ascCredentialFieldStyle(uppercase: true)

                fieldStatus(
                    value: trimmedKeyId,
                    isComplete: isKeyIdValid,
                    emptyMessage: String(localized: "Paste the 10-character Key ID."),
                    invalidMessage: String(localized: "Key ID is usually 10 uppercase letters and numbers.")
                )
            }

            // On iOS, LabeledContent gives its trailing content a flexible frame, which
            // balloons this row to a huge height inside a grouped Form — use a plain HStack
            // there. macOS keeps LabeledContent for proper label-column alignment.
            #if os(macOS)
            LabeledContent("Private Key (.p8)") { privateKeyControls }
            #else
            HStack {
                Text("Private Key (.p8)")
                Spacer()
                privateKeyControls
            }
            #endif

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if credentials.hasPrivateKey {
                Text("Private key imported. App Store Connect lets you download a .p8 key only once, so keep the original file somewhere safe.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            // macOS: compact right-aligned buttons. iOS: full-width form-row actions with
            // standard (≥44pt) tap targets.
            #if os(macOS)
            HStack {
                Spacer()
                Button {
                    Task { await runTest() }
                } label: {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
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

            if credentials.isConfigured || credentials.hasPrivateKey {
                #if os(macOS)
                HStack {
                    Spacer()
                    Button("Clear Credentials…", role: .destructive) {
                        showClearConfirmation = true
                    }
                    .controlSize(.small)
                }
                #else
                Button("Clear Credentials…", role: .destructive) {
                    showClearConfirmation = true
                }
                .frame(maxWidth: .infinity)
                #endif
            }
        } header: {
            Text("API Key")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Use an App Store Connect API key with access to edit app metadata. Account Holder, Admin, or App Manager roles are typical for screenshot uploads.")
                Text("Values are saved automatically on this Mac. The private key is stored in Keychain.")
                Text("Testing lists one app from the account. If this passes but uploads fail, check that the API key can edit the specific app and version.")
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var privateKeyControls: some View {
        // Small control size keeps the macOS row compact; iOS uses the default size so the
        // Replace/Remove tap targets meet the ~44pt minimum.
        HStack(spacing: 6) {
            if credentials.hasPrivateKey {
                Label("Imported", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Button("Replace…") { fileImporterPresented = true }
                    .buttonStyle(.bordered)
                    .ascCompactControlSize()
                Button("Remove") {
                    credentials.deletePrivateKey()
                    testResult = nil
                }
                .buttonStyle(.bordered)
                .ascCompactControlSize()
            } else {
                Button("Import .p8 File…") { fileImporterPresented = true }
                    .buttonStyle(.bordered)
            }
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
            Text(setupSummary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
        }
    }

    private var helpSection: some View {
        Section("Actions") {
            Link("Open API Keys", destination: Self.apiKeysURL)
            Link("Create or manage API keys", destination: Self.apiKeysURL)
            Link("App Store Connect API documentation", destination: Self.docsURL)
        }
    }

    private enum StatusState {
        case demoMode, connected, readyToTest, finishSetup
    }

    private var statusState: StatusState {
        if credentials.isDemoMode { return .demoMode }
        if connectionTestPassed { return .connected }
        return credentials.isConfigured ? .readyToTest : .finishSetup
    }

    private var statusMessage: String {
        switch statusState {
        case .demoMode:
            return String(localized: "Demo mode is on. The upload wizard runs against built-in sample data and never contacts App Store Connect.")
        case .connected:
            return String(localized: "The API key is connected and ready for screenshot uploads.")
        case .readyToTest:
            return String(localized: "Run the connection test once before uploading screenshots.")
        case .finishSetup:
            return String(localized: "Complete the API key details below, then test the connection.")
        }
    }

    private var demoModeSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { credentials.isDemoMode },
                set: { newValue in
                    credentials.isDemoMode = newValue
                    testResult = nil
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable demo mode")
                        .fontWeight(.medium)
                    Text("Browse a sample app, version, locales, and run a simulated upload — no API key required and no traffic is sent to App Store Connect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)

            if credentials.isDemoMode {
                Label("Demo mode is active. Real API key fields above are ignored until you turn demo mode off.",
                      systemImage: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("App Review Demo Mode")
        } footer: {
            Text("Use demo mode to walk through the App Store Connect upload feature without an API key — for example during App Review.")
                .foregroundStyle(.secondary)
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
        switch statusState {
        case .demoMode: return String(localized: "Demo mode")
        case .connected: return String(localized: "Connected")
        case .readyToTest: return String(localized: "Ready to test")
        case .finishSetup: return String(localized: "Finish setup")
        }
    }

    private var statusSymbolName: String {
        switch statusState {
        case .demoMode: return "theatermasks.fill"
        case .connected: return "checkmark.seal.fill"
        case .readyToTest: return "bolt.horizontal.circle.fill"
        case .finishSetup: return "key.horizontal"
        }
    }

    private var statusSymbolColor: Color {
        switch statusState {
        case .demoMode: return .blue
        case .connected: return .green
        case .readyToTest: return .orange
        case .finishSetup: return .secondary
        }
    }

    private var setupSummary: String {
        let checks = [isIssuerIdValid, isKeyIdValid, credentials.hasPrivateKey, connectionTestPassed]
        let complete = checks.filter { $0 }.count
        return String(localized: "\(complete) of \(checks.count) complete")
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

private extension View {
    /// Credential field chrome. macOS keeps the rounded-border box; iOS uses the plain
    /// grouped-Form cell (no box-in-a-box) and disables autocorrect/autocapitalization for
    /// these opaque identifiers.
    @ViewBuilder
    func ascCredentialFieldStyle(uppercase: Bool = false) -> some View {
        #if os(macOS)
        textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .textContentType(.oneTimeCode)
        #else
        font(.system(.body, design: .monospaced))
            .textInputAutocapitalization(uppercase ? .characters : .never)
            .autocorrectionDisabled()
        #endif
    }

    /// `.controlSize(.small)` on macOS only; iOS keeps the default size for ≥44pt tap targets.
    @ViewBuilder
    func ascCompactControlSize() -> some View {
        #if os(macOS)
        controlSize(.small)
        #else
        self
        #endif
    }
}
