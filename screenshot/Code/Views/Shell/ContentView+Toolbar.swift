import SwiftUI

extension ContentView {
    @ToolbarContentBuilder
    var mainToolbar: some CustomizableToolbarContent {
        // On iPad the Projects home screen + back button own project navigation,
        // so the editor toolbar drops the project name / actions menu.
        #if os(macOS)
        ToolbarItem(id: "projectSwitcher", placement: .navigation) {
            projectSwitcherToolbarMenu
        }

        ToolbarItem(id: "projectActions", placement: .navigation) {
            projectActionsToolbarMenu
        }
        #endif

        #if os(macOS)
        ToolbarItem(id: "export", placement: .principal) {
            exportControlGroup
        }

        if !store.isProUnlocked {
            ToolbarItem(id: "buyPro", placement: .principal) {
                Button {
                    store.presentPaywall(for: .general)
                } label: {
                    Label("Upgrade to Pro", systemImage: "crown")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Unlock all projects, rows, and templates")
                .coachPopover(step: .pro, coach: state.coach, arrowEdge: .top)
            }
        }

        ToolbarItem(id: "trailingControls", placement: .primaryAction) {
            HStack(spacing: 6) {
                if isSelectionInspectorEnabled {
                    InsertShapeToolbarMenu(state: state)
                    Divider()
                        .frame(height: 16)
                }
                if BetaFeatures.shared.isABTestingEnabled {
                    VariantsToolbarMenu(state: state)
                    Divider()
                        .frame(height: 16)
                }
                ZoomControls(onFit: fitZoomToWindow, fitHelpText: fitZoomHelpText)
                Divider()
                    .frame(height: 16)
                inspectorToggleButton
            }
        }
        #else
        // Compact width (iPhone, narrow Split View) keeps the title in the roomy
        // center slot and drops the Buy Pro capsule — the leading cluster can't
        // also fit the title next to back/undo/redo/locale there.
        if horizontalSizeClass == .compact {
            ToolbarItem(id: "iPadTitleCompact", placement: .principal) {
                iPadProjectTitleMenu
            }
        } else {
            if !store.isProUnlocked {
                ToolbarItem(id: "iPadBuyPro", placement: .principal) {
                    iPadBuyProButton
                        .coachPopover(step: .pro, coach: state.coach, arrowEdge: .top)
                }
            }

            ToolbarItem(id: "iPadTitle", placement: .topBarLeading) {
                iPadProjectTitleMenu
            }
        }

        ToolbarItem(id: "iPadUndo", placement: .navigation) {
            iPadUndoButton
        }
        ToolbarItem(id: "iPadRedo", placement: .navigation) {
            iPadRedoButton
        }
        ToolbarItem(id: "iPadLocale", placement: .navigation) {
            LocaleToolbarButton(state: state)
        }

        ToolbarItem(id: "iPadZoom", placement: .primaryAction) {
            iPadZoomMenu
        }
        ToolbarItem(id: "iPadInspector", placement: .primaryAction) {
            inspectorToggleButton
        }
        ToolbarItem(id: "iPadExport", placement: .primaryAction) {
            iPadExportControl
        }
        #endif
    }
}
