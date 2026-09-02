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
    func testAddProviderWorkflowOpensInSimplifiedChinese() {
        let app = launchApp(language: "zh-Hans")

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 4))
        app.buttons["设置"].click()

        let addProvider = app.buttons["add-model-provider-button"]
        XCTAssertTrue(addProvider.waitForExistence(timeout: 4))
        if !addProvider.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(addProvider.isHittable)
        addProvider.click()

        let heading = app.staticTexts["add-provider-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 4))
        XCTAssertEqual(heading.value as? String, "添加模型供应商")
        XCTAssertTrue(app.textFields["provider-id-field"].exists)
        XCTAssertTrue(app.textFields["provider-base-url-field"].exists)
        XCTAssertTrue(app.textFields["provider-model-id-field"].exists)
        XCTAssertTrue(app.buttons["confirm-add-provider-button"].exists)
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
