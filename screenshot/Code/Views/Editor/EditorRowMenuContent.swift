import SwiftUI

struct EditorRowMenuContent: View {
    @Bindable var state: AppState
    @Environment(StoreService.self) private var store
    let row: ScreenshotRow
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    let confirmBeforeDeleting: Bool
    @Binding var isSvgDialogPresented: Bool
    @Binding var isResettingRow: Bool
    @Binding var isDeletingRow: Bool
    let addShapeFromMenu: (ShapeType) -> Void
    let exportRowScreenshots: () -> Void
    let exportRowImage: (Bool) -> Void

    var body: some View {
        addSection
        Divider()
        organizationSection
        Divider()
        exportSection
        Divider()
        appearanceSection
        Divider()
        destructiveSection
    }

    @ViewBuilder
    private var addSection: some View {
        Button("Add Screenshot") {
            store.requirePro(
                allowed: store.canAddTemplate(currentCount: row.templates.count),
                context: .templateLimit
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.addTemplate(to: row.id)
                }
            }
        }
        Menu("Add Element") {
            ForEach(ShapeType.allCases, id: \.self) { type in
                Button {
                    if type == .svg {
                        state.selectRow(row.id)
                        isSvgDialogPresented = true
                    } else {
                        addShapeFromMenu(type)
                    }
                } label: {
                    Label(type.label, systemImage: type.icon)
                }
            }
        }
    }

    @ViewBuilder
    private var organizationSection: some View {
        Button("Duplicate Row") {
            store.requirePro(
                allowed: store.canAddRow(currentCount: state.rows.count),
                context: .rowLimit
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { state.duplicateRow(row.id) }
            }
        }
        Button("Add New Row Above") {
            store.requirePro(
                allowed: store.canAddRow(currentCount: state.rows.count),
                context: .rowLimit
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { state.addRowAbove(row.id) }
            }
        }
        Button("Add New Row Below") {
            store.requirePro(
                allowed: store.canAddRow(currentCount: state.rows.count),
                context: .rowLimit
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { state.addRowBelow(row.id) }
            }
        }
        Button("Move Row Up") {
            withAnimation(.easeInOut(duration: 0.2)) { state.moveRowUp(row.id) }
        }
        .disabled(!canMoveUp)
        Button("Move Row Down") {
            withAnimation(.easeInOut(duration: 0.2)) { state.moveRowDown(row.id) }
        }
        .disabled(!canMoveDown)
    }

    @ViewBuilder
    private var exportSection: some View {
        Menu("Export Row") {
            Button("Screenshots") {
                exportRowScreenshots()
            }
            Button("Continuous") {
                exportRowImage(false)
            }
            Button("Showcase") {
                exportRowImage(true)
            }
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Menu("Devices") {
            Button(row.showDevice ? String(localized: "Hide Devices") : String(localized: "Show Devices")) {
                state.toggleShowDevice(for: row.id)
            }
            Divider()
            Menu("Center All") {
                Button("Vertically") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.centerAllDevices(in: row.id, axis: .vertically)
                    }
                }
                Button("Horizontally") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.centerAllDevices(in: row.id, axis: .horizontally)
                    }
                }
                Button("Screenshot Center") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.centerAllDevices(in: row.id, axis: .both)
                    }
                }
            }
            Menu("Change All To") {
                DeviceMenuContent(
                    onSelectCategory: { category in
                        state.changeAllDevices(in: row.id, toCategory: category)
                    },
                    onSelectFrame: { frame in
                        state.changeAllDevices(in: row.id, toFrame: frame)
                    },
                    selectedCategory: row.defaultDeviceCategory,
                    selectedFrameId: row.defaultDeviceFrameId
                )
            }
            Divider()
            Button("Reset All Images", role: .destructive) {
                state.clearAllDeviceImages(in: row.id)
            }
        }
        Button(row.showBorders ? String(localized: "Hide Borders") : String(localized: "Show Borders")) {
            state.toggleShowBorders(for: row.id)
        }
    }

    @ViewBuilder
    private var destructiveSection: some View {
        Menu("Delete all") {
            ForEach(ShapeType.allCases, id: \.self) { type in
                Button(type.pluralLabel, role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.deleteAllShapes(ofType: type, in: row.id)
                    }
                }
            }
        }
        Button("Reset Row", role: .destructive) {
            if confirmBeforeDeleting {
                isResettingRow = true
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { state.resetRow(row.id) }
            }
        }
        Button("Delete Row", role: .destructive) {
            if confirmBeforeDeleting {
                isDeletingRow = true
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { state.deleteRow(row.id) }
            }
        }
        .disabled(!canDelete)
    }
}
