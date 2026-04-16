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

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            credentialsSection
            connectionSection
            helpSection
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: Self.p8ContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
    }

    private var credentialsSection: some View {
        Section {
            TextField("Issuer ID",
                      text: $credentials.issuerId,
                      prompt: Text("e.g. 57246542-96fe-1a63-e053-0824d011072a"))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            TextField("Key ID",
                      text: $credentials.keyId,
                      prompt: Text("10-character key ID"))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

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
                Text(importError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        } header: {
            Text("API Key")
        } footer: {
            Text("Create an API key in App Store Connect → Users and Access → Integrations → App Store Connect API. The .p8 key file is downloaded once at creation time.")
                .foregroundStyle(.secondary)
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            HStack {
                Button {
                    Task { await runTest() }
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(!credentials.isConfigured || isTesting)
                Spacer()
            }

            switch testResult {
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            case nil:
                EmptyView()
            }
        }
    }

    private var helpSection: some View {
        Section("Help") {
            Link("Create or manage API keys", destination: Self.apiKeysURL)
            Link("App Store Connect API documentation", destination: Self.docsURL)
        }
    }

    private static let p8ContentTypes: [UTType] = [UTType(filenameExtension: "p8") ?? .data]

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
                importError = "That doesn't look like a valid .p8 private key."
                return
            }
            try credentials.savePrivateKey(pem)
            testResult = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func runTest() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let message = try await AppStoreConnectAPIService.shared.testConnection()
            testResult = .success(message)
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }
}

#Preview {
    AppStoreConnectSettingsView()
        .frame(width: 520, height: 560)
}
