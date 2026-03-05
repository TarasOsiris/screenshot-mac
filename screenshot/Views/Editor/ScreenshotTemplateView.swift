import SwiftUI

struct ScreenshotTemplateView: View {
    let template: ScreenshotTemplate
    let displayWidth: CGFloat
    let displayHeight: CGFloat
    var bgColor: Color = .blue
    var onDelete: (() -> Void)?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(bgColor.gradient)
                .frame(width: displayWidth, height: displayHeight)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if let onDelete {
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(6)
                                .background(.black.opacity(0.3), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}
