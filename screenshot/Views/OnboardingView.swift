import SwiftUI

struct OnboardingView: View {
    @AppStorage("defaultScreenshotSize") private var defaultScreenshotSize = "1242x2688"
    @AppStorage("defaultTemplateCount") private var defaultTemplateCount = 3
    @AppStorage("defaultDeviceCategory") private var defaultDeviceCategoryRaw = "iphone"
    @AppStorage("defaultDeviceFrameId") private var defaultDeviceFrameId = ""
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            settingsForm
            Divider()
            footer
        }
        .frame(width: 480, height: 520)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 160, height: 160)

            Text("Welcome to Screenshot Bro")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Set up your defaults to get started. You can change these later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    // MARK: - Settings

    private var settingsForm: some View {
        Form {
            ScreenshotSizePicker(selection: $defaultScreenshotSize, label: "Screenshot size")
            DefaultDevicePicker(categoryRaw: $defaultDeviceCategoryRaw, frameId: $defaultDeviceFrameId)
            TemplateCountPicker(selection: $defaultTemplateCount, label: "Screenshots per row")
        }
        .formStyle(.grouped)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Get Started") {
                onboardingCompleted = true
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(20)
    }
}

#Preview {
    OnboardingView()
}
