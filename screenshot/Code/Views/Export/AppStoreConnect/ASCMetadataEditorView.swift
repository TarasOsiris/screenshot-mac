#if os(macOS)
import AppKit
#endif
import SwiftUI

/// The App Store Connect wizard's metadata step: per-version tabs, a locale list and the form.
struct ASCMetadataEditorView: View {
    @Bindable var model: ASCUploadFlowModel

    var body: some View {
        VStack(spacing: 0) {
            if model.selectedVersions.count > 1 {
                metadataVersionTabs
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            if let app = model.selectedApp, let version = model.activeMetadataVersion {
                ASCAppHeaderView(
                    app: app,
                    subtitle: "Version \(version.attributes.versionString) · \(version.attributes.displayState)"
                )
                .padding(.horizontal, 16)
                .padding(.top, model.selectedVersions.count > 1 ? 8 : 12)
                .padding(.bottom, 8)
            }

            #if os(macOS)
            HStack(alignment: .top, spacing: 0) {
                metadataLocaleSidebar
                    .frame(width: 180)
                Divider()
                metadataFormPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #else
            metadataLocalePicker
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            Divider()
            metadataFormPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
    }

    /// One tab per selected version (shown when 2+ versions are selected), so per-version
    /// metadata (release notes, copyright, …) can be edited without leaving the screen.
    var metadataVersionTabs: some View {
        Picker("Version", selection: $model.metadataVersionId) {
            ForEach(model.selectedVersions) { version in
                Text(metadataTabLabel(version)).tag(version.id as String?)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: model.metadataVersionId) { _, _ in
            model.keepSelectedMetadataLocaleValid()
        }
    }

    func metadataTabLabel(_ version: ASCAppStoreVersion) -> String {
        if let platform = version.attributes.displayPlatform {
            return "\(platform) \(version.attributes.versionString)"
        }
        return version.attributes.versionString
    }

    #if os(iOS)
    /// iPad replacement for the desktop locale sidebar: a pull-down menu above the form. Each
    /// row (and the current selection) shows a change-dot mirroring the sidebar's indicators.
    var metadataLocalePicker: some View {
        let changedLocales = model.metadataLocalesWithChanges
        return Menu {
            ForEach(model.metadataLocaleCodes, id: \.self) { code in
                Button {
                    model.selectedMetadataLocale = code
                } label: {
                    if changedLocales.contains(code) {
                        Label(code, systemImage: "pencil.circle.fill")
                    } else {
                        Text(code)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text(model.selectedMetadataLocale ?? model.metadataLocaleCodes.first ?? "")
                    .fontWeight(.medium)
                if let selected = model.selectedMetadataLocale, changedLocales.contains(selected) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.blue)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    #endif

    #if os(macOS)
    var metadataLocaleSidebar: some View {
        let changedLocales = model.metadataLocalesWithChanges
        return List(selection: Binding(
            get: { model.selectedMetadataLocale },
            set: { model.selectedMetadataLocale = $0 }
        )) {
            Section("Version") {
                HStack {
                    Text("All locales")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.activeVersionCopyrightChanged {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.blue)
                    }
                }
            }
            Section("Locales") {
                ForEach(model.metadataLocaleCodes, id: \.self) { code in
                    HStack {
                        Text(code)
                        Spacer()
                        if changedLocales.contains(code) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.blue)
                        }
                    }
                    .tag(code as String?)
                }
            }
        }
        .listStyle(.sidebar)
    }
    #endif

    @ViewBuilder
    var metadataFormPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                versionCopyrightField
                if let code = model.selectedMetadataLocale {
                    if let idx = model.appInfoDrafts.firstIndex(where: { $0.locale == code }) {
                        appInfoSection(index: idx)
                    }
                    if let idx = model.versionDrafts.firstIndex(where: { $0.versionId == model.metadataVersionId && $0.locale == code }) {
                        versionLocaleSection(index: idx)
                    }
                    if !model.versionDrafts.contains(where: { $0.versionId == model.metadataVersionId && $0.locale == code }),
                       !model.appInfoDrafts.contains(where: { $0.locale == code }) {
                        Text("No editable metadata for this locale.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } else {
                    Text("Select a locale on the left to edit its metadata.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(16)
        }
    }

    var versionCopyrightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Copyright")
                .font(.subheadline)
                .fontWeight(.semibold)
            TextField("© 2025 Your Company", text: Binding(
                get: { model.copyrightByVersion[model.metadataVersionId ?? ""] ?? "" },
                set: { model.copyrightByVersion[model.metadataVersionId ?? ""] = $0 }
            ))
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
            Text("Applies to all locales for this version.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    func appInfoSection(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App Info (shared across versions)")
                .font(.subheadline)
                .fontWeight(.semibold)
            metadataField(
                label: "App Name",
                text: $model.appInfoDrafts[index][.name],
                field: .name
            )
            metadataField(
                label: "Subtitle",
                text: $model.appInfoDrafts[index][.subtitle],
                field: .subtitle
            )
            metadataField(
                label: "Privacy Policy URL",
                text: $model.appInfoDrafts[index][.privacyPolicyUrl],
                field: .privacyPolicyUrl
            )
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    func versionLocaleSection(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This Version")
                .font(.subheadline)
                .fontWeight(.semibold)
            metadataField(
                label: "What's New",
                text: $model.versionDrafts[index][.whatsNew],
                field: .whatsNew,
                multiline: true,
                minHeight: 80
            )
            if model.canCopyWhatsNewToOtherLocales(from: index) {
                Button("Copy to all locales") {
                    model.copyWhatsNewToOtherLocales(from: index)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            metadataField(
                label: "Promotional Text",
                text: $model.versionDrafts[index][.promotionalText],
                field: .promotionalText,
                multiline: true,
                minHeight: 44
            )
            metadataField(
                label: "Description",
                text: $model.versionDrafts[index][.description],
                field: .description,
                multiline: true,
                minHeight: 140
            )
            metadataField(
                label: "Keywords (comma-separated)",
                text: $model.versionDrafts[index][.keywords],
                field: .keywords
            )
            metadataField(
                label: "Support URL",
                text: $model.versionDrafts[index][.supportUrl],
                field: .supportUrl
            )
            metadataField(
                label: "Marketing URL",
                text: $model.versionDrafts[index][.marketingUrl],
                field: .marketingUrl
            )
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    func metadataField(
        label: LocalizedStringKey,
        text: Binding<String>,
        field: ASCMetadataField,
        multiline: Bool = false,
        minHeight: CGFloat = 0
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let limit = field.limit {
                    let count = text.wrappedValue.count
                    Text("\(count)/\(limit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(count > limit ? .red : .secondary)
                }
            }
            if multiline {
                #if os(macOS)
                PlainTextEditor(text: text, font: .preferredFont(forTextStyle: .body))
                    .frame(minHeight: minHeight)
                    .padding(4)
                    .background(Color.platformTextBackground, in: .rect(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    }
                #else
                // iOS: a native auto-growing multi-line field rather than a hand-bordered TextEditor.
                TextField("", text: text, axis: .vertical)
                    .lineLimit(3...)
                    .textFieldStyle(.roundedBorder)
                #endif
            } else {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    #if os(iOS)
                    .keyboardType(field.isURL ? .URL : .default)
                    .textInputAutocapitalization(field.isURL ? .never : nil)
                    .autocorrectionDisabled(field.isURL)
                    #endif
            }
        }
    }
}
