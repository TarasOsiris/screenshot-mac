import AppKit
import SwiftUI

private struct ASCAppIconView: View {
    let bundleId: String
    let size: CGFloat

    @State private var iconURL: URL?

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                    case .failure, .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .task(id: bundleId) {
            iconURL = await AppStoreConnectIconFetcher.shared.iconURL(forBundleId: bundleId)
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
            Image(systemName: "app.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: size * 0.45))
        }
    }
}

private struct ASCAppHeaderView: View {
    let app: ASCApp
    let subtitle: String
    var iconSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            ASCAppIconView(bundleId: app.attributes.bundleId, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.attributes.name)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct UploadToAppStoreConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state

    @State private var step: Step = .pickingApp
    @State private var apps: [ASCApp] = []
    @State private var selectedApp: ASCApp?

    @State private var versions: [ASCAppStoreVersion] = []
    @State private var selectedVersion: ASCAppStoreVersion?

    @State private var localizations: [ASCAppStoreVersionLocalization] = []

    @State private var rowPlans: [RowPlan] = []
    @State private var uploadProgress: ASCUploadProgress?
    @State private var uploadTask: Task<Void, Never>?
    @State private var uploadSummary: UploadSummary?

    @State private var errorMessage: String?
    @State private var uploadFailureDetails: String?
    @State private var displayTypeDetailsPlanId: UUID?
    @State private var isBusy = false

    struct UploadSummary {
        let appId: String?
        let appName: String
        let totalScreenshots: Int
        let localizationCount: Int
    }

    @State private var credentials = AppStoreConnectCredentialsStore.shared

    private enum Step {
        case pickingApp
        case pickingVersion
        case configuringPlan
        case uploading
        case done
    }

    struct RowPlan: Identifiable {
        let id: UUID
        var rowLabel: String
        var rowSize: CGSize
        var templateCount: Int
        var isEnabled: Bool
        var detectedDisplayType: ASCDisplayType?
        var selectedDisplayType: ASCDisplayType?
        var localeTargets: [LocaleTarget]
    }

    struct LocaleTarget: Identifiable {
        let id = UUID()
        var appLocaleCode: String
        var appLocaleLabel: String
        var selectedASCLocalizationId: String?
        var candidates: [ASCAppStoreVersionLocalization]
        var isEnabled: Bool
    }

    struct UploadPlanEntry: Identifiable {
        let id: String
        let rowLabel: String
        let sourceSizeLabel: String
        let displayTypeLabel: String
        let displayTypeRawValue: String
        let projectLocaleLabel: String
        let projectLocaleCode: String
        let appStoreLocaleCode: String?
        let templateCount: Int
        let isSelected: Bool
        let skipReason: String?

        var screenshotCount: Int { isSelected ? templateCount : 0 }
    }

    struct UploadLocaleGroup: Identifiable {
        let id: String
        let label: String
        let entries: [UploadPlanEntry]

        var screenshotCount: Int { entries.reduce(0) { $0 + $1.screenshotCount } }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 860, height: 680)
        .task { await loadAppsIfNeeded() }
        .alert("Upload failed", isPresented: Binding(
            get: { uploadFailureDetails != nil },
            set: { isPresented in
                if !isPresented { uploadFailureDetails = nil }
            }
        )) {
            Button("Copy Details") {
                if let uploadFailureDetails {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(uploadFailureDetails, forType: .string)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(uploadFailureDetails ?? "")
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
            Text("Upload to App Store Connect")
                .font(.headline)
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(alignment: .top) {
            backButton
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            dismissButton
            primaryButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var backButton: some View {
        switch step {
        case .pickingVersion, .configuringPlan:
            Button {
                goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(isBusy)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        switch step {
        case .uploading:
            Button("Cancel Upload", role: .cancel) { cancelUpload() }
        case .done:
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .pickingApp:
            Button("Next") { Task { await moveToVersion() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedApp == nil || isBusy)
        case .pickingVersion:
            Button("Next") { Task { await moveToPlan() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvanceFromVersion || isBusy)
        case .configuringPlan:
            Button("Upload") { Task { await startUpload() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canStartUpload || isBusy)
        case .uploading, .done:
            EmptyView()
        }
    }

    private var canAdvanceFromVersion: Bool {
        guard let version = selectedVersion else { return false }
        return version.isEditable
    }

    private func goBack() {
        errorMessage = nil
        uploadFailureDetails = nil
        switch step {
        case .pickingVersion:
            step = .pickingApp
        case .configuringPlan:
            step = .pickingVersion
        default: break
        }
    }

    private func cancelUpload() {
        uploadTask?.cancel()
    }

    private var validationIssues: [ASCUploadIssue] {
        guard let version = selectedVersion else { return [] }
        return ASCUploadValidator.validate(version: version, plans: rowPlans)
    }

    private var canStartUpload: Bool {
        !validationIssues.hasErrors
    }

    private var uploadPlanEntries: [UploadPlanEntry] {
        rowPlans.flatMap { plan -> [UploadPlanEntry] in
            guard plan.isEnabled else { return [] }
            let rowLabel = plan.rowLabel.isEmpty ? "Row" : plan.rowLabel
            let sourceSizeLabel = "\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))"
            let displayTypeLabel = plan.selectedDisplayType?.label ?? "No display type selected"
            let displayTypeRawValue = plan.selectedDisplayType?.rawValue ?? "none"

            return plan.localeTargets.map { target in
                let appStoreLocale = target.selectedASCLocalizationId.flatMap { selectedId in
                    target.candidates.first(where: { $0.id == selectedId })?.attributes.locale
                }
                let isSelected = target.isEnabled && plan.selectedDisplayType != nil && appStoreLocale != nil
                let skipReason: String?
                if isSelected {
                    skipReason = nil
                } else if target.candidates.isEmpty {
                    skipReason = "No matching App Store locale"
                } else if !target.isEnabled {
                    skipReason = "Unchecked"
                } else if plan.selectedDisplayType == nil {
                    skipReason = "No display type selected"
                } else {
                    skipReason = "No App Store locale selected"
                }

                return UploadPlanEntry(
                    id: "\(plan.id.uuidString)-\(target.id.uuidString)",
                    rowLabel: rowLabel,
                    sourceSizeLabel: sourceSizeLabel,
                    displayTypeLabel: displayTypeLabel,
                    displayTypeRawValue: displayTypeRawValue,
                    projectLocaleLabel: target.appLocaleLabel,
                    projectLocaleCode: target.appLocaleCode,
                    appStoreLocaleCode: appStoreLocale,
                    templateCount: plan.templateCount,
                    isSelected: isSelected,
                    skipReason: skipReason
                )
            }
        }
    }

    private var selectedUploadPlanEntries: [UploadPlanEntry] {
        uploadPlanEntries.filter(\.isSelected)
    }

    private var skippedUploadPlanEntries: [UploadPlanEntry] {
        uploadPlanEntries.filter { !$0.isSelected }
    }

    private var selectedLocaleGroups: [UploadLocaleGroup] {
        let grouped = Dictionary(grouping: selectedUploadPlanEntries) { entry in
            entry.appStoreLocaleCode ?? entry.projectLocaleCode
        }
        return grouped.keys.sorted().map { code in
            let entries = grouped[code] ?? []
            let label = entries.first.map { "\($0.projectLocaleLabel) -> \(code)" } ?? code
            return UploadLocaleGroup(id: code, label: label, entries: entries)
        }
    }

    // MARK: - Content by step

    @ViewBuilder
    private var content: some View {
        if !credentials.isConfigured {
            missingCredentialsView
        } else {
            switch step {
            case .pickingApp: pickAppView
            case .pickingVersion: pickVersionView
            case .configuringPlan: configurePlanView
            case .uploading, .done: uploadProgressView
            }
        }
    }

    private var missingCredentialsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("App Store Connect API key required")
                .font(.headline)
            Text("Add your Issuer ID, Key ID, and .p8 key in Settings → App Store Connect.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pickAppView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select an app")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            List(selection: Binding(
                get: { selectedApp?.id },
                set: { newId in selectedApp = apps.first(where: { $0.id == newId }) }
            )) {
                ForEach(apps) { app in
                    ASCAppHeaderView(app: app, subtitle: app.attributes.bundleId, iconSize: 36)
                        .tag(app.id as String?)
                }
            }
            .listStyle(.inset)
        }
    }

    private var pickVersionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select a version")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            if let app = selectedApp {
                ASCAppHeaderView(app: app, subtitle: app.attributes.bundleId)
                    .padding(.horizontal, 16)
            }
            List(selection: Binding(
                get: { selectedVersion?.id },
                set: { newId in selectedVersion = versions.first(where: { $0.id == newId }) }
            )) {
                ForEach(versions) { version in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(version.attributes.versionString)
                                    .fontWeight(.medium)
                                if let platform = version.attributes.displayPlatform {
                                    Text(platform)
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.15), in: .capsule)
                                }
                            }
                            Text(version.attributes.displayState)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !version.isEditable {
                            Label("Read-only", systemImage: "lock.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                    .tag(version.id as String?)
                }
            }
            .listStyle(.inset)
            if let version = selectedVersion, !version.isEditable {
                Label("This version is \(version.attributes.displayState) — screenshots can't be changed. Pick an editable version or create a new one in App Store Connect.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
        }
    }

    private var configurePlanView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let app = selectedApp, let version = selectedVersion {
                    ASCAppHeaderView(
                        app: app,
                        subtitle: "Version \(version.attributes.versionString) · \(version.attributes.displayState)"
                    )
                }

                Text("Review and upload plan")
                    .font(.headline)

                uploadSummaryPanel

                replaceWarningCallout

                issuesPanel

                ForEach($rowPlans) { $plan in
                    rowPlanCard(plan: $plan)
                }
            }
            .padding(16)
        }
    }

    private var uploadSummaryPanel: some View {
        let entries = selectedUploadPlanEntries
        let screenshotCount = entries.reduce(0) { $0 + $1.screenshotCount }
        let issues = validationIssues

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preflight")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if issues.hasErrors {
                    Label("Fix required", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                } else {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Button("Refresh App Store data") {
                    Task { await refreshLocalizations() }
                }
                .font(.caption)
                .disabled(isBusy)
            }

            HStack(spacing: 10) {
                summaryMetric("\(entries.count)", "sets")
                summaryMetric("\(screenshotCount)", "screenshots")
                summaryMetric("\(selectedLocaleGroups.count)", "locales")
            }

            if !selectedLocaleGroups.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected uploads")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(selectedLocaleGroups) { group in
                        localePlanGroupRow(group)
                    }
                }
            }

            if !skippedUploadPlanEntries.isEmpty {
                DisclosureGroup("Skipped items (\(skippedUploadPlanEntries.count))") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(skippedUploadPlanEntries.prefix(12)) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text("\(entry.projectLocaleLabel) · \(entry.rowLabel): \(entry.skipReason ?? "Skipped")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if skippedUploadPlanEntries.count > 12 {
                            Text("\(skippedUploadPlanEntries.count - 12) more skipped item\(skippedUploadPlanEntries.count - 12 == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private func summaryMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 78, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 6))
    }

    private func localePlanGroupRow(_ group: UploadLocaleGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(group.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(group.screenshotCount) screenshot\(group.screenshotCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(group.entries) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(entry.rowLabel) -> \(entry.displayTypeLabel)")
                            .font(.caption)
                            .lineLimit(1)
                        Text("Source \(entry.sourceSizeLabel) · \(entry.templateCount) screenshot\(entry.templateCount == 1 ? "" : "s") · \(entry.displayTypeRawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: 6))
    }

    private var replaceWarningCallout: some View {
        calloutBox(tint: .orange) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                        .font(.system(size: 13))
                    Text("Existing screenshots in each matching display type set will be deleted and replaced. This cannot be undone.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !selectedUploadPlanEntries.isEmpty {
                    Text("The selected upload plan will replace or create these App Store screenshot sets.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var issuesPanel: some View {
        let issues = validationIssues
        if !issues.isEmpty {
            calloutBox(tint: issues.hasErrors ? .red : .orange) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(issues) { issue in
                        issueRow(issue)
                    }
                }
            }
        }
    }

    private func calloutBox<Content: View>(tint: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 1)
            )
    }

    private func issueRow(_ issue: ASCUploadIssue) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity.tint)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                issueMessageText(issue)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = issue.hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func issueMessageText(_ issue: ASCUploadIssue) -> Text {
        if let scope = issue.scope {
            return Text(scope).fontWeight(.semibold) + Text(" · ") + Text(issue.message)
        }
        return Text(issue.message)
    }

    private func rowPlanCard(plan: Binding<RowPlan>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(isOn: plan.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.wrappedValue.rowLabel.isEmpty ? "Row" : plan.wrappedValue.rowLabel)
                            .fontWeight(.medium)
                        Text("\(Int(plan.wrappedValue.rowSize.width))×\(Int(plan.wrappedValue.rowSize.height)) · \(plan.wrappedValue.templateCount) screenshot\(plan.wrappedValue.templateCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
            }

            if plan.wrappedValue.isEnabled {
                displayTypePicker(plan: plan)

                HStack {
                    Text("Locales")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh locales") {
                        Task { await refreshLocalizations() }
                    }
                    .font(.caption)
                    .disabled(isBusy)
                }
                ForEach(plan.localeTargets) { $target in
                    localeTargetRow(target: $target)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private func displayTypePicker(plan: Binding<RowPlan>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Text("\(Int(plan.wrappedValue.rowSize.width))×\(Int(plan.wrappedValue.rowSize.height))")
                    .font(.caption)
                if let detected = plan.wrappedValue.detectedDisplayType,
                   detected == plan.wrappedValue.selectedDisplayType {
                    Label("Auto-detected", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Spacer()
                Button {
                    displayTypeDetailsPlanId = plan.wrappedValue.id
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(
                    get: { displayTypeDetailsPlanId == plan.wrappedValue.id },
                    set: { isPresented in
                        if !isPresented { displayTypeDetailsPlanId = nil }
                    }
                )) {
                    displayTypeDetailsPopover(plan: plan.wrappedValue)
                }
            }
            HStack {
                Text("Upload as")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Picker("", selection: plan.selectedDisplayType) {
                    Text("Select…").tag(ASCDisplayType?.none)
                    ForEach(ASCDisplayType.userSelectableCases) { type in
                        Text(type.label).tag(Optional(type))
                    }
                }
                .labelsHidden()
                if let selected = plan.wrappedValue.selectedDisplayType {
                    Text(selected.rawValue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func displayTypeDetailsPopover(plan: RowPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Type")
                .font(.headline)
            LabeledContent("Source size") {
                Text("\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))")
            }
            LabeledContent("Auto-detected") {
                Text(plan.detectedDisplayType?.label ?? "No exact match")
            }
            if let selected = plan.selectedDisplayType {
                LabeledContent("Upload target") {
                    Text(selected.label)
                }
                LabeledContent("ASC value") {
                    Text(selected.rawValue)
                        .font(.caption.monospaced())
                }
                LabeledContent("Accepted sizes") {
                    Text(selected.acceptedSizeDescription)
                        .multilineTextAlignment(.trailing)
                }
                if selected.family == .ipad {
                    Label("App Store Connect rejects this if the selected app version is iPhone-only.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func localeTargetRow(target: Binding<LocaleTarget>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(isOn: target.isEnabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.wrappedValue.appLocaleLabel)
                    Text("Project \(target.wrappedValue.appLocaleCode)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 150, alignment: .leading)
            }
            .toggleStyle(.checkbox)
            .disabled(target.wrappedValue.candidates.isEmpty)

            if target.wrappedValue.candidates.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No matching App Store locale")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Add this locale in App Store Connect, then refresh locales.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("", selection: target.selectedASCLocalizationId) {
                    Text("Choose…").tag(String?.none)
                    ForEach(target.wrappedValue.candidates) { candidate in
                        Text(candidate.attributes.locale).tag(Optional(candidate.id))
                    }
                }
                .labelsHidden()
                .disabled(!target.wrappedValue.isEnabled)
                if let selectedId = target.wrappedValue.selectedASCLocalizationId,
                   let selected = target.wrappedValue.candidates.first(where: { $0.id == selectedId }) {
                    Text("-> \(selected.attributes.locale)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var uploadProgressView: some View {
        Group {
            if step == .done {
                doneView
            } else {
                inProgressView
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inProgressView: some View {
        VStack(spacing: 16) {
            if let progress = uploadProgress {
                ProgressView(value: Double(progress.completedSteps), total: Double(max(progress.totalSteps, 1)))
                Text(progress.currentLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(progress.completedSteps) / \(progress.totalSteps)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private var doneView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Upload complete")
                .font(.title3)
                .fontWeight(.semibold)
            if let summary = uploadSummary {
                Text("\(summary.totalScreenshots) screenshot\(summary.totalScreenshots == 1 ? "" : "s") uploaded across \(summary.localizationCount) locale\(summary.localizationCount == 1 ? "" : "s").")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let appId = summary.appId,
                   let url = URL(string: "https://appstoreconnect.apple.com/apps/\(appId)/appstore") {
                    Link(destination: url) {
                        Label("Open \(summary.appName) in App Store Connect", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Step transitions

    private func loadAppsIfNeeded() async {
        guard credentials.isConfigured, apps.isEmpty else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            apps = try await AppStoreConnectAPIService.shared.listApps()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveToVersion() async {
        guard let app = selectedApp else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            versions = try await AppStoreConnectAPIService.shared.listAppStoreVersions(appId: app.id)
            selectedVersion = versions.first(where: { $0.isEditable }) ?? versions.first
            step = .pickingVersion
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveToPlan() async {
        guard let version = selectedVersion else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            localizations = try await AppStoreConnectAPIService.shared.listLocalizations(versionId: version.id)
            rowPlans = buildRowPlans(preserving: rowPlans)
            step = .configuringPlan
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLocalizations() async {
        guard let version = selectedVersion else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            localizations = try await AppStoreConnectAPIService.shared.listLocalizations(versionId: version.id)
            rowPlans = buildRowPlans(preserving: rowPlans)
        } catch {
            errorMessage = "Could not refresh locales: \(error.localizedDescription)"
        }
    }

    private func buildRowPlans(preserving existingPlans: [RowPlan] = []) -> [RowPlan] {
        state.rows.map { row in
            let detected = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight)
            let existingPlan = existingPlans.first(where: { $0.id == row.id })
            let targets = state.localeState.locales.map { locale -> LocaleTarget in
                let matches = ASCLocaleMatcher.matches(appCode: locale.code, in: localizations)
                let existingTarget = existingPlan?.localeTargets.first(where: { $0.appLocaleCode == locale.code })
                let preservedSelection = existingTarget?.selectedASCLocalizationId
                let selectedId: String?
                if let preservedSelection, matches.contains(where: { $0.id == preservedSelection }) {
                    selectedId = preservedSelection
                } else {
                    selectedId = matches.first?.id
                }
                return LocaleTarget(
                    appLocaleCode: locale.code,
                    appLocaleLabel: locale.flagLabel,
                    selectedASCLocalizationId: selectedId,
                    candidates: matches,
                    isEnabled: matches.isEmpty ? false : (existingTarget?.isEnabled ?? true)
                )
            }
            return RowPlan(
                id: row.id,
                rowLabel: row.label,
                rowSize: CGSize(width: row.templateWidth, height: row.templateHeight),
                templateCount: row.templates.count,
                isEnabled: existingPlan?.isEnabled ?? true,
                detectedDisplayType: detected,
                selectedDisplayType: existingPlan?.selectedDisplayType ?? detected,
                localeTargets: targets
            )
        }
    }

    private func startUpload() async {
        errorMessage = nil
        uploadFailureDetails = nil
        let issues = validationIssues
        guard !issues.hasErrors else {
            errorMessage = "Fix the preflight errors before uploading."
            return
        }
        let targets = buildUploadTargets()
        guard !targets.isEmpty else {
            errorMessage = "No rows × locales are selected."
            step = .configuringPlan
            return
        }

        step = .uploading
        isBusy = true
        defer { isBusy = false; uploadTask = nil }

        let task = Task {
            do {
                try await AppStoreConnectUploadService.shared.upload(
                    targets: targets,
                    appState: state,
                    progress: { p in self.uploadProgress = p }
                )
                if Task.isCancelled { return }
                uploadSummary = UploadSummary(
                    appId: selectedApp?.id,
                    appName: selectedApp?.attributes.name ?? "",
                    totalScreenshots: targets.reduce(0) { $0 + $1.templateCount * $1.localizations.count },
                    localizationCount: Set(targets.flatMap { $0.localizations.map(\.id) }).count
                )
                step = .done
            } catch is CancellationError {
                errorMessage = "Upload cancelled. Screenshot sets for already-started locales may have been cleared but not refilled — re-run the upload to restore them, or check App Store Connect."
                step = .configuringPlan
            } catch {
                errorMessage = uploadFailureSummary(for: error)
                uploadFailureDetails = uploadFailureDetails(for: error)
                step = .configuringPlan
            }
        }
        uploadTask = task
        await task.value
    }

    private func buildUploadTargets() -> [ASCUploadTarget] {
        rowPlans.compactMap { plan -> ASCUploadTarget? in
            guard plan.isEnabled, let displayType = plan.selectedDisplayType else { return nil }
            let localizations = plan.localeTargets.compactMap { target -> ASCUploadLocalization? in
                guard target.isEnabled, let id = target.selectedASCLocalizationId else { return nil }
                return ASCUploadLocalization(id: id, label: target.appLocaleLabel, localeCode: target.appLocaleCode)
            }
            guard !localizations.isEmpty else { return nil }
            return ASCUploadTarget(
                rowId: plan.id,
                rowLabel: plan.rowLabel.isEmpty ? "Row" : plan.rowLabel,
                rowSize: plan.rowSize,
                displayType: displayType,
                localizations: localizations,
                templateCount: plan.templateCount
            )
        }
    }

    private func uploadFailureSummary(for error: Error) -> String {
        if let uploadError = error as? AppStoreConnectUploadError {
            return uploadError.summaryDescription
        }
        return "Upload failed: \(error.localizedDescription)"
    }

    private func uploadFailureDetails(for error: Error) -> String {
        var details: [String] = [error.localizedDescription]
        if let app = selectedApp {
            details.append("App: \(app.attributes.name) (\(app.attributes.bundleId))")
        }
        if let version = selectedVersion {
            let platform = version.attributes.displayPlatform.map { " \($0)" } ?? ""
            details.append("Version: \(version.attributes.versionString)\(platform) · \(version.attributes.displayState)")
        }
        if let uploadError = error as? AppStoreConnectUploadError {
            details.append("Technical details:\n\(uploadError.technicalDescription)")
        }
        return details.joined(separator: "\n\n")
    }
}
