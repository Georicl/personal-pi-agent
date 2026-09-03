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
        XCTAssertTrue(app.popUpButtons["default-provider-picker"].exists)
        XCTAssertTrue(app.popUpButtons["default-model-picker"].exists)
        XCTAssertTrue(app.buttons["enabled-models-menu"].exists)
        XCTAssertTrue(app.buttons["包与资源"].exists)
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
        XCTAssertTrue(app.buttons["Packages"].exists)
        let overviewExists = app.buttons["Overview"].exists
        XCTAssertTrue(overviewExists)
    }

    @MainActor
    func testPackagesAndResourcesPageUsesPiSnapshot() {
        let app = launchApp(language: "zh-Hans")

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        let packages = app.buttons["包与资源"]
        XCTAssertTrue(packages.waitForExistence(timeout: 4))
        packages.click()

        XCTAssertTrue(app.staticTexts["packages-heading"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.textFields["package-source-input"].exists)
        XCTAssertTrue(app.buttons["install-package-button"].exists)
        XCTAssertTrue(app.buttons["refresh-packages-button"].exists)
        XCTAssertTrue(app.buttons["save-resource-paths-button"].exists)
    }

    @MainActor
    func testNativeProviderLoginPickerOpensInSimplifiedChinese() {
        let app = launchApp(language: "zh-Hans")

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 4))
        app.buttons["设置"].click()

        let configureProvider = app.buttons["configure-model-provider-button"]
        XCTAssertTrue(configureProvider.waitForExistence(timeout: 4))
        if !configureProvider.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(configureProvider.isHittable)
        configureProvider.click()

        let heading = app.staticTexts["provider-login-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 4))
        XCTAssertEqual(heading.value as? String, "模型供应商账户")

        let codexProvider = app.buttons["provider-row-openai-codex"]
        let deepSeekProvider = app.buttons["provider-row-deepseek"]
        XCTAssertTrue(codexProvider.waitForExistence(timeout: 4))
        XCTAssertTrue(deepSeekProvider.exists)
        codexProvider.click()
        XCTAssertTrue(app.buttons["begin-provider-login-button"].exists)
        XCTAssertTrue(app.buttons["logout-provider-button"].exists)
    }

    @MainActor
    func testLogoutSlashCommandOpensStoredProviderPicker() {
        let app = launchApp(language: "zh-Hans")

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        let composer = app.textFields["composer-input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 4))
        composer.click()
        composer.typeText("/logout deepseek")
        composer.typeKey(.return, modifierFlags: [])

        let heading = app.staticTexts["provider-login-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 4))
        XCTAssertEqual(heading.value as? String, "退出模型供应商")
        XCTAssertTrue(app.buttons["provider-row-deepseek"].exists)
        XCTAssertTrue(app.buttons["logout-provider-button"].exists)
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
