import XCTest

final class PersonalPiUITests: XCTestCase {
    private var dataRoot: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        dataRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalPiUITests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let dataRoot {
            try? FileManager.default.removeItem(at: dataRoot)
        }
    }

    @MainActor
    func testSimplifiedChineseNavigationAndSettings() {
        let app = launchApp(language: "zh-Hans")

        let windowExists = app.windows.firstMatch.waitForExistence(timeout: 8)
        XCTAssertTrue(windowExists)
        let settingsExists = app.buttons["设置"].waitForExistence(timeout: 4)
        XCTAssertTrue(settingsExists)
        app.buttons["设置"].click()
        let headingExists = app.staticTexts["Pi 设置"].waitForExistence(timeout: 4)
        XCTAssertTrue(headingExists)
        let languageExists = app.staticTexts["界面语言"].exists
        XCTAssertTrue(languageExists)
        let overviewExists = app.buttons["总览"].exists
        XCTAssertTrue(overviewExists)
    }

    @MainActor
    func testEnglishNavigationAndSettings() {
        let app = launchApp(language: "en")

        let windowExists = app.windows.firstMatch.waitForExistence(timeout: 8)
        XCTAssertTrue(windowExists)
        let settingsExists = app.buttons["Settings"].waitForExistence(timeout: 4)
        XCTAssertTrue(settingsExists)
        app.buttons["Settings"].click()
        let headingExists = app.staticTexts["Pi settings"].waitForExistence(timeout: 4)
        XCTAssertTrue(headingExists)
        let languageExists = app.staticTexts["Interface language"].exists
        XCTAssertTrue(languageExists)
        let overviewExists = app.buttons["Overview"].exists
        XCTAssertTrue(overviewExists)
    }

    @MainActor
    private func launchApp(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PERSONAL_PI_UI_TESTING"] = "1"
        app.launchEnvironment["PERSONAL_PI_DATA_ROOT"] = dataRoot.path
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-\(appLanguageStorageKey)", language,
        ]
        app.launch()
        return app
    }

    private var appLanguageStorageKey: String { "personalPi.appLanguage" }
}
