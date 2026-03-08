import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("defaultScreenshotSize") private var defaultScreenshotSize = "1242x2688"
    @AppStorage("exportFormat") private var exportFormat = "png"
    @AppStorage("exportScale") private var exportScale = 1.0
    @AppStorage("openExportFolderOnSuccess") private var openExportFolderOnSuccess = true
    @AppStorage("defaultTemplateCount") private var defaultTemplateCount = 3
    @AppStorage("defaultZoomLevel") private var defaultZoomLevel = 1.0

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                generalSettings
            }

            Tab("Export", systemImage: "square.and.arrow.up") {
                exportSettings
            }
        }
        .frame(width: 420, height: 260)
    }

    private var generalSettings: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("Auto").tag("auto")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }

            Picker("Default screenshot size", selection: $defaultScreenshotSize) {
                ForEach(displayCategories) { category in
                    Section(category.name) {
                        ForEach(category.sizes) { size in
                            Text(size.label)
                                .tag("\(Int(size.width))x\(Int(size.height))")
                        }
                    }
                }
            }

            Picker("Screenshots per new row", selection: $defaultTemplateCount) {
                ForEach(1...6, id: \.self) { count in
                    Text(verbatim: "\(count)").tag(count)
                }
            }

            Picker("Default zoom level", selection: $defaultZoomLevel) {
                Text("25%").tag(0.25)
                Text("50%").tag(0.50)
                Text("75%").tag(0.75)
                Text("100%").tag(1.0)
                Text("125%").tag(1.25)
                Text("150%").tag(1.50)
                Text("175%").tag(1.75)
                Text("200%").tag(2.0)
            }
        }
        .formStyle(.grouped)
    }

    private var exportSettings: some View {
        Form {
            Picker("Format", selection: $exportFormat) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpeg")
            }

            Picker("Scale", selection: $exportScale) {
                Text("1x").tag(1.0)
                Text("2x").tag(2.0)
                Text("3x").tag(3.0)
            }

            Toggle("Open export folder after completion", isOn: $openExportFolderOnSuccess)
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
}
