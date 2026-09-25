import SwiftUI

enum VariantPalette {
    private static let colors: [Color] = [.purple, .orange, .teal, .pink, .green, .indigo]

    static func color(for variantId: UUID?, in variants: [ScreenshotVariant]) -> Color {
        guard let position = variants.firstIndex(where: { $0.id == variantId }) else { return .secondary }
        let slot = (variants[position].colorIndex ?? position) % colors.count
        return colors[slot < 0 ? slot + colors.count : slot]
    }
}

/// A row's badge, computed once for the whole list so rows take it as a value, not by reading `state.variants`.
struct VariantBadgeStyle: Equatable {
    let name: String
    let tint: Color
    var hasSizeClash = false

    func clashing(_ clash: Bool) -> VariantBadgeStyle {
        VariantBadgeStyle(name: name, tint: clash ? .orange : tint, hasSizeClash: clash)
    }

    static var original: VariantBadgeStyle { VariantBadgeStyle(name: String(localized: "Original"), tint: .secondary) }

    static func byVariantId(_ variants: [ScreenshotVariant]) -> [UUID: VariantBadgeStyle] {
        // Keeps the first on a duplicate id rather than trapping on a damaged file.
        Dictionary(variants.map { variant in
            (variant.id, VariantBadgeStyle(name: variant.name, tint: VariantPalette.color(for: variant.id, in: variants)))
        }, uniquingKeysWith: { first, _ in first })
    }
}

/// A row's variant UI state, computed once for the whole list so a row never reads `state.rows`.
struct RowVariantContext: Equatable {
    let badge: VariantBadgeStyle
    let variants: [ScreenshotVariant]
    let filter: EditorVariantFilter
    /// Variant id → label of the row already holding this row's screenshot size there.
    let occupants: [UUID: String]
    let isLabelLinked: Bool

    /// Keyed by row id; empty while the project has no variants.
    static func all(for state: AppState) -> [UUID: RowVariantContext] {
        let variants = state.activeVariants
        guard !variants.isEmpty else { return [:] }
        let badges = VariantBadgeStyle.byVariantId(variants)
        let occupancy = state.variantSlotOccupancy()
        let filter = state.effectiveVariantFilter
        let hasHandNamedRow = Dictionary(state.rows.map { ($0.id, $0.isLabelManuallySet) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(state.rows.map { row in
            let badge = row.variantId.flatMap { badges[$0] }?.clashing(occupancy.clashing.contains(row.id)) ?? .original
            // Mirrors `AppState.labelSource(of:)`.
            let isLinked = row.variantId != nil && row.originRowId.map { $0 != row.id && hasHandNamedRow[$0] == true } == true
            return (row.id, RowVariantContext(
                badge: badge,
                variants: variants,
                filter: filter,
                occupants: occupancy.occupants[row.id] ?? [:],
                isLabelLinked: isLinked
            ))
        }, uniquingKeysWith: { first, _ in first })
    }
}

struct VariantBadge: View {
    let name: String
    let tint: Color
    var hasSizeClash = false

    var body: some View {
        Label(name, systemImage: hasSizeClash ? "exclamationmark.triangle.fill" : "square.split.2x1")
            .labelStyle(.titleAndIcon)
            .scaledFont(UIMetrics.FontSize.numericBadge, weight: .medium)
            .lineLimit(1)
            .fixedSize()
            .statusBadgeCapsule(tint)
    }
}

/// "Original" plus each variant, tagged `UUID?`, for any picker that assigns a variant.
struct VariantPickerOptions: View {
    let variants: [ScreenshotVariant]
    var isAvailable: (ScreenshotVariant) -> Bool = { _ in true }

    var body: some View {
        Text("Original").tag(UUID?.none)
        ForEach(variants) { variant in
            Text(variant.name).tag(Optional(variant.id))
                .disabled(!isAvailable(variant))
        }
    }
}

/// The row header's badge, which is also the quickest way to filter by, move or rename its variant.
struct VariantBadgeMenu: View {
    @Bindable var state: AppState
    let row: ScreenshotRow
    let context: RowVariantContext
    @State private var renaming: ScreenshotVariant?

    var body: some View {
        let style = context.badge
        let filter: EditorVariantFilter = .variant(row.variantId)
        Menu {
            if context.filter == filter {
                Button("Show All Variants", systemImage: "square.stack") { state.setVariantFilter(.all) }
            } else {
                Button("Show Only \(style.name)", systemImage: "line.3.horizontal.decrease") { state.setVariantFilter(filter) }
            }
            Divider()
            RowVariantMoveMenu(state: state, row: row, context: context)
            if let variant = context.variants.variant(withId: row.variantId) {
                Button("Rename Variant…", systemImage: "pencil") { renaming = variant }
            }
        } label: {
            VariantBadge(name: style.name, tint: style.tint, hasSizeClash: style.hasSizeClash)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(style.hasSizeClash
            ? "\(style.name) has another row of this screenshot size. A variant holds one row per size — move or delete one."
            : "Variant options")
        .variantRenameAlert(state: state, variant: $renaming)
    }
}

/// The row menu's variant items: branch this row into a new variant, copy it into another, or move it.
struct RowVariantMenuItems: View {
    @Bindable var state: AppState
    @Environment(PurchaseService.self) private var store
    let row: ScreenshotRow
    /// nil until the project has a variant.
    let context: RowVariantContext?

    var body: some View {
        Button("New Variant from Row", systemImage: "square.split.2x1") {
            requireRowSlot { state.createVariant(fromRow: row.id) }
        }
        if let context {
            Menu {
                if !row.isOriginal {
                    Button("Original") { requireRowSlot { state.duplicateRow(row.id, into: nil) } }
                }
                ForEach(context.variants.filter { $0.id != row.variantId }) { variant in
                    VariantTargetButton(variant: variant, occupant: context.occupants[variant.id]) {
                        requireRowSlot { state.duplicateRow(row.id, into: variant.id) }
                    }
                }
            } label: {
                Label("Copy Row to Variant", systemImage: "plus.square.on.square")
            }
            RowVariantMoveMenu(state: state, row: row, context: context)
        }
    }

    private func requireRowSlot(_ action: @escaping () -> Void) {
        store.requirePro(allowed: store.canAddRow(currentCount: state.rows.count), context: .rowLimit) {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        }
    }
}

private struct RowVariantMoveMenu: View {
    @Bindable var state: AppState
    let row: ScreenshotRow
    let context: RowVariantContext

    var body: some View {
        Menu {
            Button {
                state.setRowVariant(row.id, to: nil)
            } label: {
                if row.isOriginal { Label("Original", systemImage: "checkmark") } else { Text("Original") }
            }
            .disabled(row.isOriginal)
            ForEach(context.variants) { variant in
                if variant.id == row.variantId {
                    Button {} label: { Label(variant.name, systemImage: "checkmark") }
                        .disabled(true)
                } else {
                    VariantTargetButton(variant: variant, occupant: context.occupants[variant.id]) {
                        state.setRowVariant(row.id, to: variant.id)
                    }
                }
            }
        } label: {
            Label("Move Row to Variant", systemImage: "arrow.right.square")
        }
    }
}

/// A variant as a copy/move destination, disabled with the reason when it already has a row this size.
private struct VariantTargetButton: View {
    let variant: ScreenshotVariant
    let occupant: String?
    let action: () -> Void

    var body: some View {
        if let occupant {
            Button(String(localized: "\(variant.name) — already has \(occupant)"), action: {})
                .disabled(true)
        } else {
            Button(variant.name, action: action)
        }
    }
}

/// Filters the editor to one variant, starts new ones, and renames or deletes them.
struct VariantsToolbarMenu: View {
    @Bindable var state: AppState
    @Environment(PurchaseService.self) private var store
    @State private var renaming: ScreenshotVariant?
    @State private var deleting: ScreenshotVariant?

    private var filter: EditorVariantFilter { state.effectiveVariantFilter }

    var body: some View {
        let variants = state.activeVariants
        let rowCounts = Dictionary(grouping: state.rows, by: \.variantId).mapValues(\.count)
        Menu {
            if !variants.isEmpty {
                Picker("Show", selection: Binding(get: { filter }, set: { state.setVariantFilter($0) })) {
                    Text("All Variants").tag(EditorVariantFilter.all)
                    Text("Original").tag(EditorVariantFilter.variant(nil))
                    ForEach(variants) { variant in
                        Text(variant.name).tag(EditorVariantFilter.variant(variant.id))
                    }
                }
                .pickerStyle(.inline)
                Divider()
            }
            Button("New Variant from Selected Row", systemImage: "plus") {
                guard let rowId = state.selectedRowId else { return }
                store.requirePro(allowed: store.canAddRow(currentCount: state.rows.count), context: .rowLimit) {
                    withAnimation(.easeInOut(duration: 0.2)) { state.createVariant(fromRow: rowId) }
                }
            }
            .disabled(state.selectedRowId == nil)
            if !variants.isEmpty {
                Menu("Rename") {
                    ForEach(variants) { variant in
                        Button(variant.name) { renaming = variant }
                    }
                }
                Menu("Delete") {
                    ForEach(variants) { variant in
                        Button(role: .destructive) { deleting = variant } label: {
                            Text(verbatim: "\(variant.name) — \(Self.rowCountText(rowCounts[variant.id] ?? 0))")
                        }
                    }
                }
            }
            if variants.count > ASCExperiment.maxTreatments {
                Divider()
                Text("An App Store experiment tests up to 3 variants.")
            }
        } label: {
            Label(filterTitle, systemImage: "square.split.2x1")
                .labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .help("A/B variants: show one, start a new one, or rename and delete them")
        .variantRenameAlert(state: state, variant: $renaming)
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Variant", role: .destructive) {
                if let deleting { state.deleteVariant(deleting.id) }
            }
        } message: {
            Text(deleteMessage(rowCount: deleting.map { rowCounts[$0.id] ?? 0 } ?? 0))
        }
    }

    private var filterTitle: String {
        switch filter {
        case .all: String(localized: "Variants")
        case .variant(nil): String(localized: "Original")
        case .variant(let id?): state.activeVariants.variant(withId: id)?.name ?? String(localized: "Variants")
        }
    }

    private var deleteTitle: String {
        String(localized: "Delete “\(deleting?.name ?? "")”?")
    }

    /// Mirrors `deleteVariant`: rows that are all the project has move to the Original instead.
    private func deleteMessage(rowCount: Int) -> String {
        if rowCount == 0 { return String(localized: "It has no rows. You can undo this.") }
        if rowCount == state.rows.count { return String(localized: "Its rows are all this project has, so they move to the Original. You can undo this.") }
        return String(localized: "Its \(Self.rowCountText(rowCount)) are deleted too. You can undo this.")
    }

    private static func rowCountText(_ count: Int) -> String {
        String(localized: "^[\(count) row](inflect: true)")
    }
}

private struct VariantRenameAlert: ViewModifier {
    @Bindable var state: AppState
    @Binding var variant: ScreenshotVariant?
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: variant?.id) { name = variant?.name ?? "" }
            .alert("Rename Variant", isPresented: Binding(get: { variant != nil }, set: { if !$0 { variant = nil } })) {
                TextField("Name", text: $name)
                Button("Rename") {
                    if let variant { state.renameVariant(variant.id, to: name) }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

private extension View {
    func variantRenameAlert(state: AppState, variant: Binding<ScreenshotVariant?>) -> some View {
        modifier(VariantRenameAlert(state: state, variant: variant))
    }
}
