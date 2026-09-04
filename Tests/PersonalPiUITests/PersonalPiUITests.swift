import CoreGraphics
import ImageIO
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
        XCTAssertTrue(app.descendants(matching: .any)["enabled-models-menu"].exists)
        XCTAssertTrue(app.buttons["包与资源"].exists)
        XCTAssertTrue(app.staticTexts["高级运行环境"].exists)
        XCTAssertTrue(app.disclosureTriangles["advanced-runtime-disclosure"].exists)
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
    func testFigurePreviewSidebarCanBeOpenedFromAnyPage() throws {
        try prepareFigureArtifact()
        let app = launchApp(language: "zh-Hans")

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        let toggle = app.buttons["figure-artifact-sidebar-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 4))
        toggle.click()
        XCTAssertTrue(app.descendants(matching: .any)["figure-artifact-sidebar"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["figure-artifact-image"].exists)
        XCTAssertTrue(app.buttons["export-figure-button"].exists)

        app.buttons["知识库"].click()
        XCTAssertTrue(app.descendants(matching: .any)["figure-artifact-sidebar"].exists)
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
            let settingsScrollView = app.scrollViews["settings-scroll-view"]
            XCTAssertTrue(settingsScrollView.exists)
            settingsScrollView.scroll(byDeltaX: 0, deltaY: -120)
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
    func testNativeSessionCommandsAppearInComposer() {
        let app = launchApp(language: "en")

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        let composer = app.textFields["composer-input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 4))
        composer.click()

        assertSlashCommand("/tree", using: "/tr", in: composer, app: app)
        assertSlashCommand("/fork", using: "/fo", in: composer, app: app)
        assertSlashCommand("/clone", using: "/cl", in: composer, app: app)
        assertSlashCommand("/export", using: "/ex", in: composer, app: app)
    }

    @MainActor
    func testSessionInformationSheetUsesSimplifiedChinese() {
        let app = launchApp(language: "zh-Hans")

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        let composer = app.textFields["composer-input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 4))
        composer.click()
        composer.typeText("/session ")
        composer.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.staticTexts["会话信息"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["运行标识、存储位置与当前用量"].exists)
        XCTAssertTrue(app.staticTexts["名称"].exists)
        XCTAssertTrue(app.staticTexts["尚未持久化"].exists)
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

    private func prepareFigureArtifact() throws {
        let versionDirectory = dataRoot
            .appendingPathComponent("chat/.pi/artifacts/figures/ui-test/v001", isDirectory: true)
        let preview = versionDirectory.appendingPathComponent("figure.png")
        let index = dataRoot
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("personal-pi-figure-artifacts.json")
        try FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: index.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: 320,
                height: 120,
                bitsPerComponent: 8,
                bytesPerRow: 320 * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw NSError(domain: "PersonalPiUITests", code: 1)
        }
        context.setFillColor(CGColor(red: 0.93, green: 0.96, blue: 0.99, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 120))
        context.setFillColor(CGColor(red: 0.23, green: 0.43, blue: 0.65, alpha: 1))
        context.fill(CGRect(x: 30, y: 20, width: 65, height: 70))
        context.fill(CGRect(x: 125, y: 20, width: 65, height: 45))
        context.fill(CGRect(x: 220, y: 20, width: 65, height: 82))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                preview as CFURL,
                "public.png" as CFString,
                1,
                nil
              ) else {
            throw NSError(domain: "PersonalPiUITests", code: 2)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "PersonalPiUITests", code: 3)
        }

        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "kind": "scientific-figure",
            "id": "ui-test-v001",
            "figureId": "ui-test",
            "version": 1,
            "title": "UI test figure",
            "sessionId": NSNull(),
            "cwd": dataRoot.appendingPathComponent("chat", isDirectory: true).path,
            "createdAt": "2026-09-04T08:30:00Z",
            "previewPath": preview.path,
            "files": [["format": "png", "path": preview.path]],
            "widthMm": 210,
            "heightMm": 74.25,
            "dpi": 300,
            "validation": [
                "passed": true,
                "score": 100,
                "errors": [],
                "warnings": [],
                "checks": [],
            ],
            "intermediatesRetained": false,
        ]
        var data = try JSONSerialization.data(withJSONObject: [manifest], options: [.prettyPrinted])
        data.append(0x0A)
        try data.write(to: index, options: .atomic)
    }

    private var appLanguageStorageKey: String { "personalPi.appLanguage" }

    @MainActor
    private func assertSlashCommand(
        _ command: String,
        using query: String,
        in composer: XCUIElement,
        app: XCUIApplication
    ) {
        composer.typeKey("a", modifierFlags: .command)
        composer.typeText(query)
        let commandButton = app.buttons["slash-command-\(command.dropFirst())"]
        XCTAssertTrue(commandButton.waitForExistence(timeout: 4))
        XCTAssertTrue(commandButton.label.contains(command))
    }
}
