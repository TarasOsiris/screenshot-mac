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

    @MainActor
    func testMainWindowCanBeReopenedAndBlankProjectRestoresEditor() throws {
        let dataDirectory = makeTempDataDirectory()
        defer { try? FileManager.default.removeItem(at: dataDirectory) }

        let app = XCUIApplication()
        app.launchEnvironment["SCREENSHOT_DATA_DIR"] = dataDirectory.path
        app.launchEnvironment["SCREENSHOT_FORCE_PRO_UNLOCK"] = "1"
        app.launchArguments += ["-onboardingCompleted", "YES"]
        app.launch()

        let mainWindow = app.windows["Screenshot Bro"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10))

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(mainWindow.waitForNonExistence(timeout: 5))

        app.menuBars.menuBarItems["Window"].click()
        let showMainWindowItem = app.menuItems["Show Main Window"]
        XCTAssertTrue(showMainWindowItem.waitForExistence(timeout: 2))
        showMainWindowItem.click()
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(mainWindow.waitForNonExistence(timeout: 5))

        app.typeKey("n", modifierFlags: .command)

        let newProjectWindow = app.windows["New Project"]
        XCTAssertTrue(newProjectWindow.waitForExistence(timeout: 5))

        let createBlankProjectButton = newProjectWindow.buttons["Create Blank Project"]
        XCTAssertTrue(createBlankProjectButton.waitForExistence(timeout: 2))
        createBlankProjectButton.click()

        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(newProjectWindow.waitForNonExistence(timeout: 5))
    }

    private func makeTempDataDirectory() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("screenshot-ui-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
