import SwiftUI

enum VariantPalette {
    private static let colors: [Color] = [.purple, .orange, .teal, .pink, .green, .indigo]

    static func color(for variantId: UUID?, in variants: [ScreenshotVariant]) -> Color {
        guard let index = variants.firstIndex(where: { $0.id == variantId }) else { return .secondary }
        return colors[index % colors.count]
    }
}

/// A row's badge, computed once for the whole list so rows take it as a value, not by reading `state.variants`.
struct VariantBadgeStyle: Equatable {
    let name: String
    let tint: Color

    static func byVariantId(_ variants: [ScreenshotVariant]) -> [UUID: VariantBadgeStyle] {
        Dictionary(uniqueKeysWithValues: variants.map { variant in
            (variant.id, VariantBadgeStyle(name: variant.name, tint: VariantPalette.color(for: variant.id, in: variants)))
        })
    }
}

struct VariantBadge: View {
    let name: String
    let tint: Color

    var body: some View {
        Label(name, systemImage: "square.split.2x1")
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

    var body: some View {
        Text("Original").tag(UUID?.none)
        ForEach(variants) { variant in
            Text(variant.name).tag(Optional(variant.id))
        }
    }
}

/// The row menu's variant items: branch this row into a variant, or move it between them.
struct RowVariantMenuItems: View {
    @Bindable var state: AppState
    @Environment(PurchaseService.self) private var store
    let row: ScreenshotRow

    var body: some View {
        Menu {
            Button("New Variant", systemImage: "plus") {
                requireRowSlot { state.createVariant(fromRow: row.id) }
            }
            if !state.variants.isEmpty || !row.isOriginal {
                Divider()
            }
            if !row.isOriginal {
                Button("Original") {
                    requireRowSlot { state.duplicateRow(row.id, into: nil) }
                }
            }
            ForEach(state.variants.filter { $0.id != row.variantId }) { variant in
                Button(variant.name) {
                    requireRowSlot { state.duplicateRow(row.id, into: variant.id) }
                }
            }
        } label: {
            Label("Duplicate as Variant", systemImage: "square.split.2x1")
        }

        if !state.variants.isEmpty {
            Picker(selection: Binding(
                get: { row.variantId },
                set: { state.setRowVariant(row.id, to: $0) }
            )) {
                VariantPickerOptions(variants: state.variants)
            } label: {
                Label("Move to Variant", systemImage: "arrow.right.square")
            }
            .pickerStyle(.menu)
        }
    }

    private func requireRowSlot(_ action: @escaping () -> Void) {
        store.requirePro(allowed: store.canAddRow(currentCount: state.rows.count), context: .rowLimit) {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        }
    }
}

/// Filters the editor to one variant and manages the variant list. Shown once a variant exists.
struct VariantsToolbarMenu: View {
    @Bindable var state: AppState
    @State private var renaming: ScreenshotVariant?
    @State private var renameText = ""
    @State private var deleting: ScreenshotVariant?

    private var filter: EditorVariantFilter { state.effectiveVariantFilter }

    var body: some View {
        Menu {
            Picker("Show", selection: Binding(
                get: { filter },
                set: { state.viewMode.variantFilter = $0 }
            )) {
                Text("All Variants").tag(EditorVariantFilter.all)
                Text("Original").tag(EditorVariantFilter.variant(nil))
                ForEach(state.variants) { variant in
                    Text(variant.name).tag(EditorVariantFilter.variant(variant.id))
                }
            }
            .pickerStyle(.inline)

            Divider()

            Menu("Rename") {
                ForEach(state.variants) { variant in
                    Button(variant.name) {
                        renameText = variant.name
                        renaming = variant
                    }
                }
            }
            Menu("Delete") {
                ForEach(state.variants) { variant in
                    Button(variant.name, role: .destructive) { deleting = variant }
                }
            }
        } label: {
            Label(filterTitle, systemImage: "square.split.2x1")
        }
        .fixedSize()
        .help("Show one A/B variant, or rename and delete variants")
        .alert("Rename Variant", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let renaming { state.renameVariant(renaming.id, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Variant", role: .destructive) {
                if let deleting { state.deleteVariant(deleting.id) }
            }
        } message: {
            Text("Its rows are deleted too. You can undo this.")
        }
    }

    private var filterTitle: String {
        switch filter {
        case .all: String(localized: "All Variants")
        case .variant(nil): String(localized: "Original")
        case .variant(let id?): state.variants.variant(withId: id)?.name ?? String(localized: "All Variants")
        }
    }

    private var deleteTitle: String {
        String(localized: "Delete “\(deleting?.name ?? "")”?")
    }
}
