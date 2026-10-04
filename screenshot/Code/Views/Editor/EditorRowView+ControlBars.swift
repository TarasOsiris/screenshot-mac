import SwiftUI

extension EditorRowView {
    @ViewBuilder
    var controlBarsRow: some View {
        LazyHStack(spacing: 0) {
            ForEach(Array(row.templates.enumerated()), id: \.element.id) { index, template in
                // Stated size, same contract as `EditorRowLayout`: the bar is pinned to its
                // column and to `TemplateBar.height`, so the stack places it by arithmetic
                // instead of descending into every `ActionButton` to measure one.
                Color.clear
                    .frame(width: row.displayWidth(zoom: zoom), height: UIMetrics.TemplateBar.height)
                    .overlay(alignment: .topLeading) {
                        TemplateControlBar(
                            template: template,
                            row: row,
                            index: index,
                            zoom: zoom,
                            screenshotImages: state.screenshotImages,
                            localeState: state.localeState,
                            canMoveLeft: index > 0,
                            canMoveRight: index < row.templates.count - 1,
                            onMoveLeft: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    state.moveTemplateLeft(template.id, in: row.id)
                                }
                            },
                            onMoveRight: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    state.moveTemplateRight(template.id, in: row.id)
                                }
                            },
                            onSave: { state.scheduleSave() },
                            // macOS file-panel path; on iPad BackgroundImageEditor picks via ImageSourceMenu
                            // and saves through onDropBackgroundImage below.
                            onPickBackgroundImage: { state.pickAndSaveBackgroundImage(for: row.id, templateIndex: index) },
                            onRemoveBackgroundImage: { state.removeBackgroundImage(for: row.id, templateIndex: index) },
                            onDropBackgroundImage: { image in
                                state.saveBackgroundImage(image, for: row.id, templateIndex: index)
                            },
                            onDropBackgroundSvg: { svgContent in
                                state.saveBackgroundSvg(svgContent, for: row.id, templateIndex: index)
                            },
                            onDuplicate: {
                                store.addTemplateIfAllowed(currentCount: row.templates.count) { state.duplicateTemplate(template.id, in: row.id) }
                            },
                            onDuplicateToEnd: {
                                store.addTemplateIfAllowed(currentCount: row.templates.count) { state.duplicateTemplateToEnd(template.id, in: row.id) }
                            },
                            onInsertBefore: {
                                store.addTemplateIfAllowed(currentCount: row.templates.count) { state.insertTemplateBefore(template.id, in: row.id) }
                            },
                            onInsertAfter: {
                                store.addTemplateIfAllowed(currentCount: row.templates.count) { state.insertTemplateAfter(template.id, in: row.id) }
                            },
                            onDelete: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    state.removeTemplate(template.id, from: row.id)
                                }
                            },
                            onLoadFullResImages: { [weak state] in
                                guard let state else { return [:] }
                                return state.loadFullResolutionImages(forRow: row, localeCode: state.localeState.activeLocaleCode)
                            }
                        )
                    }
            }
        }
        .frame(height: UIMetrics.TemplateBar.height)
    }
}
