import XCTest

final class AllItemsNavigationTests: XCTestCase {

    let app = XCUIApplication()
    let debugLogURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".garden/debug.log")

    override func setUpWithError() throws {
        continueAfterFailure = false
        if let key = ProcessInfo.processInfo.environment["GARDEN_ANTHROPIC_KEY"] {
            app.launchEnvironment["GARDEN_ANTHROPIC_KEY"] = key
        }
        app.launchEnvironment["GARDEN_SKIP_KEYCHAIN"] = "1"
        app.launch()
        sleep(2)
    }

    func testAllViewShowsItemsAfterCategoryNavigation() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Window should exist")

        // Take initial screenshot
        attach(app.screenshot(), name: "01_initial_all")

        // The sidebar is on the left side of the window. Use coordinate taps.
        // Sidebar is roughly 220px wide. Categories start below All (~80-100px from top).
        // Click somewhere in the middle of the sidebar, ~130px down (should be a category)
        let sidebarCategoryPoint = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 110, dy: 150))
        sidebarCategoryPoint.click()
        sleep(1)

        attach(app.screenshot(), name: "02_after_category_click")

        // Now clear the debug log
        try? Data().write(to: debugLogURL)

        // Click "All" — it's near the top of the sidebar, around y=55
        let allPoint = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 110, dy: 58))
        allPoint.click()
        sleep(2)

        attach(app.screenshot(), name: "03_after_all_click")

        // Read the debug log
        let log = (try? String(contentsOf: debugLogURL, encoding: .utf8)) ?? "(empty)"
        print("=== POST-NAV LOG ===")
        print(log)
        print("=== END ===")

        // The body should have been re-evaluated
        XCTAssertTrue(log.contains("[AllItemsView] body"),
            "AllItemsView body must evaluate after clicking All. Got: \(log)")
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let a = XCTAttachment(screenshot: screenshot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
