import SwiftUI

struct EditorRowView: View {
    @Bindable var state: AppState
    let row: ScreenshotRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row header
            HStack(spacing: 8) {
                Circle()
                    .fill(.blue)
                    .frame(width: 6, height: 6)

                Text(row.label)
                    .font(.system(size: 12, weight: .medium))

                Text(row.resolutionLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Template strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(row.templates) { template in
                        ScreenshotTemplateView(
                            template: template,
                            displayWidth: row.displayWidth,
                            displayHeight: row.displayHeight,
                            onDelete: row.templates.count > 1 ? {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    state.removeTemplate(template.id, from: row.id)
                                }
                            } : nil
                        )
                    }

                    // Add button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.addTemplate(to: row.id)
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(.secondary)
                            .frame(width: row.displayWidth, height: row.displayHeight)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}
