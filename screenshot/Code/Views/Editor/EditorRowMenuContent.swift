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
        Button("Add Screenshot", systemImage: "plus.rectangle") {
            store.requirePro(
                allowed: store.canAddTemplate(currentCount: row.templates.count),
                context: .templateLimit
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.addTemplate(to: row.id)
                }
            }
        }
        Menu {
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
        } label: {
            Label("Add Element", systemImage: "plus.circle")
        }
    }

    @ViewBuilder
    private var organizationSection: some View {
        Button("Duplicate Row", systemImage: "plus.square.on.square") {
            store.requirePro(
                allowed: store.canAddRow(currentCount: state.rows.count),
                context: .rowLimit
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { state.duplicateRow(row.id) }
            }
        }
        Button("Add New Row Above", systemImage: "arrow.up.to.line.compact") {
            store.requirePro(
                allowed: store.canAddRow(currentCount: state.rows.count),
                context: .rowLimit
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { state.addRowAbove(row.id) }
            }
        }
        Button("Add New Row Below", systemImage: "arrow.down.to.line.compact") {
            store.requirePro(
                allowed: store.canAddRow(currentCount: state.rows.count),
                context: .rowLimit
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { state.addRowBelow(row.id) }
            }
        }
        Button("Move Row Up", systemImage: "arrow.up") {
            withAnimation(.easeInOut(duration: 0.2)) { state.moveRowUp(row.id) }
        }
        .disabled(!canMoveUp)
        Button("Move Row Down", systemImage: "arrow.down") {
            withAnimation(.easeInOut(duration: 0.2)) { state.moveRowDown(row.id) }
        }
        .disabled(!canMoveDown)
    }

    @ViewBuilder
    private var exportSection: some View {
        Menu {
            Button("Screenshots", systemImage: "photo.on.rectangle") {
                exportRowScreenshots()
            }
            Button("Continuous", systemImage: "rectangle.split.3x1") {
                exportRowImage(false)
            }
            Button("Showcase", systemImage: "rectangle.stack") {
                exportRowImage(true)
            }
        } label: {
            Label("Export Row", systemImage: "square.and.arrow.up")
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Menu {
            Button(
                row.showDevice ? String(localized: "Hide Devices") : String(localized: "Show Devices"),
                systemImage: row.showDevice ? "eye.slash" : "eye"
            ) {
                state.toggleShowDevice(for: row.id)
            }
            Divider()
            Menu {
                Button("Vertically", systemImage: "arrow.up.and.down") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.centerAllDevices(in: row.id, axis: .vertically)
                    }
                }
                Button("Horizontally", systemImage: "arrow.left.and.right") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.centerAllDevices(in: row.id, axis: .horizontally)
                    }
                }
                Button("Screenshot Center", systemImage: "scope") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.centerAllDevices(in: row.id, axis: .both)
                    }
                }
            } label: {
                Label("Center All", systemImage: "align.horizontal.center")
            }
            Menu {
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
            } label: {
                Label("Change All To", systemImage: "arrow.triangle.2.circlepath")
            }
            Divider()
            Button("Reset All Images", systemImage: "arrow.counterclockwise", role: .destructive) {
                state.clearAllDeviceImages(in: row.id)
            }
        } label: {
            Label("Devices", systemImage: "iphone")
        }
        Button(
            row.showBorders ? String(localized: "Hide Borders") : String(localized: "Show Borders"),
            systemImage: row.showBorders ? "square" : "square.dashed"
        ) {
            state.toggleShowBorders(for: row.id)
        }
    }

    @ViewBuilder
    private var destructiveSection: some View {
        Menu {
            ForEach(ShapeType.allCases, id: \.self) { type in
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.deleteAllShapes(ofType: type, in: row.id)
                    }
                } label: {
                    Label(type.pluralLabel, systemImage: type.icon)
                }
            }
        } label: {
            Label("Delete all", systemImage: "trash")
        }
        Button("Reset Row", systemImage: "arrow.counterclockwise", role: .destructive) {
            if confirmBeforeDeleting {
                isResettingRow = true
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { state.resetRow(row.id) }
            }
        }
        Button("Delete Row", systemImage: "trash", role: .destructive) {
            if confirmBeforeDeleting {
                isDeletingRow = true
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { state.deleteRow(row.id) }
            }
        }
        .disabled(!canDelete)
    }
}
