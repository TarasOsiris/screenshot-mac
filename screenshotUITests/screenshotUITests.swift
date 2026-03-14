import XCTest

final class screenshotUITests: XCTestCase {
    @MainActor
    func testAppLaunches() throws {
        let dataDirectory = makeTempDataDirectory()
        defer { try? FileManager.default.removeItem(at: dataDirectory) }

        let app = XCUIApplication()
        app.launchEnvironment["SCREENSHOT_DATA_DIR"] = dataDirectory.path
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    private func makeTempDataDirectory() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("screenshot-ui-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
