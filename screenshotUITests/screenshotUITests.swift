import AppKit
import XCTest

final class screenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateProjectAndSimpleManipulations() throws {
        terminateExistingAppInstances()

        let dataDirectory = makeTemporaryDataDirectory()
        defer { try? FileManager.default.removeItem(at: dataDirectory) }

        let app = XCUIApplication()
        app.launchEnvironment["SCREENSHOT_DATA_DIR"] = dataDirectory.path
        app.launch()

        let projectActions = app.descendants(matching: .any)["projectActionsMenu"]
        XCTAssertTrue(projectActions.waitForExistence(timeout: 5))
        projectActions.click()

        let newProjectItem = app.menuItems["New Project..."]
        XCTAssertTrue(newProjectItem.waitForExistence(timeout: 5))
        newProjectItem.click()

        let projectPicker = app.popUpButtons["projectPicker"]
        XCTAssertTrue(projectPicker.waitForExistence(timeout: 5))
        projectPicker.click()

        XCTAssertTrue(app.menuItems["My App"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["Project 2"].waitForExistence(timeout: 5))
        app.menuItems["Project 2"].click()

        let addRowButton = app.descendants(matching: .any)["toolbarAddRowButton"].firstMatch
        XCTAssertTrue(addRowButton.waitForExistence(timeout: 5))
        addRowButton.click()
        XCTAssertTrue(app.staticTexts["Screenshot 2"].waitForExistence(timeout: 5))

        projectActions.click()
        let renameProjectItem = app.menuItems["Rename Project..."]
        XCTAssertTrue(renameProjectItem.waitForExistence(timeout: 5))
        renameProjectItem.click()

        let renameField = app.sheets.textFields["Project name"].firstMatch
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        replaceText(in: renameField, with: "UI Test Project")

        let renameButton = app.sheets.buttons["Rename"].firstMatch
        XCTAssertTrue(renameButton.waitForExistence(timeout: 5))
        renameButton.click()
        XCTAssertTrue(waitForNonExistence(app.sheets.firstMatch, timeout: 5))
        XCTAssertTrue(waitForPopUpValue(projectPicker, toContain: "UI Test Project", timeout: 5))
    }

    private func makeTemporaryDataDirectory() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = root
            .appendingPathComponent("screenshot-ui-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func terminateExistingAppInstances() {
        let bundleIdentifier = "xyz.tleskiv.screenshot"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for runningApp in runningApps where !runningApp.isTerminated {
            _ = runningApp.forceTerminate()
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let stillRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .contains(where: { !$0.isTerminated })
            if !stillRunning { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForPopUpValue(_ element: XCUIElement, toContain expected: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { evaluated, _ in
            guard let popup = evaluated as? XCUIElement else { return false }
            guard let value = popup.value as? String else { return false }
            return value.localizedCaseInsensitiveContains(expected)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        field.click()
        field.typeKey("a", modifierFlags: .command)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        field.typeKey("v", modifierFlags: .command)

        pasteboard.clearContents()
        if let previousContents {
            pasteboard.setString(previousContents, forType: .string)
        }
    }
}
