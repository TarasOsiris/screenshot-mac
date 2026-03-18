import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(StoreService.self) private var store
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("defaultScreenshotSize") private var defaultScreenshotSize = "1242x2688"
    @AppStorage("exportFormat") private var exportFormat = "png"
    @AppStorage("exportScale") private var exportScale = 1.0
    @AppStorage("openExportFolderOnSuccess") private var openExportFolderOnSuccess = true
    @AppStorage("defaultTemplateCount") private var defaultTemplateCount = 3
    @AppStorage("defaultZoomLevel") private var defaultZoomLevel = 1.0
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @AppStorage("defaultDeviceCategory") private var defaultDeviceCategoryRaw = "iphone"
    @AppStorage("defaultDeviceFrameId") private var defaultDeviceFrameId = ""

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                generalSettings
            }

            Tab("Export", systemImage: "square.and.arrow.up") {
                exportSettings
            }

            Tab("Purchase", systemImage: "star") {
                purchaseSettings
            }
        }
        .frame(width: 420, height: 380)
    }

    private var generalSettings: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("Auto").tag("auto")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }

            ScreenshotSizePicker(selection: $defaultScreenshotSize)

            DefaultDevicePicker(categoryRaw: $defaultDeviceCategoryRaw, frameId: $defaultDeviceFrameId)

            TemplateCountPicker(selection: $defaultTemplateCount)

            Toggle("Confirm before deleting", isOn: $confirmBeforeDeleting)

            Picker("Default zoom level", selection: $defaultZoomLevel) {
                Text("25%").tag(0.25)
                Text("50%").tag(0.50)
                Text("75%").tag(0.75)
                Text("100%").tag(1.0)
                Text("125%").tag(1.25)
                Text("150%").tag(1.50)
                Text("175%").tag(1.75)
                Text("200%").tag(2.0)
            }
            LabeledContent("Project storage") {
                Button("Open in Finder") {
                    NSWorkspace.shared.open(PersistenceService.rootURL)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var exportSettings: some View {
        Form {
            Picker("Format", selection: $exportFormat) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpeg")
            }

            Picker("Scale", selection: $exportScale) {
                Text("1x").tag(1.0)
                Text("2x").tag(2.0)
                Text("3x").tag(3.0)
            }

            Toggle("Open export folder after completion", isOn: $openExportFolderOnSuccess)
        }
        .formStyle(.grouped)
    }

    private var purchaseSettings: some View {
        Form {
            Section {
                LabeledContent("Plan") {
                    if store.isProUnlocked {
                        Label("Pro", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Free")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if store.isProUnlocked {
                Section("Included") {
                    proFeatureRow("Unlimited projects")
                    proFeatureRow("Unlimited rows per project")
                    proFeatureRow("Unlimited screenshots per row")
                }
            } else {
                freeTierSections
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var freeTierSections: some View {
        Section("Free plan limits") {
            limitRow("Projects", value: "1")
            limitRow("Rows per project", value: "\(StoreService.freeMaxRows)")
            limitRow("Screenshots per row", value: "\(StoreService.freeMaxTemplatesPerRow)")
        }

        Section {
            upgradeRow
            LabeledContent("Already purchased?") {
                Button("Restore Purchase") {
                    Task { await store.restore() }
                }
                .disabled(store.isLoading)
            }
        }

        if let error = store.purchaseError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }

        if let info = store.purchaseInfo {
            Section {
                Label(info, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var upgradeRow: some View {
        if let product = store.proProduct {
            LabeledContent("Upgrade to Pro") {
                Button {
                    Task { await store.purchase() }
                } label: {
                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Buy — \(product.displayPrice)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)
            }
        } else if store.didFinishLoadingProducts {
            LabeledContent("Upgrade to Pro") {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        } else {
            LabeledContent("Upgrade to Pro") {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func proFeatureRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark")
            .foregroundStyle(.primary)
    }

    private func limitRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .monospacedDigit()
        }
    }
}

#Preview {
    SettingsView()
        .environment(StoreService())
}
