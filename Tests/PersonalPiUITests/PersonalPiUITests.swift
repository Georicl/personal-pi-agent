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
        XCTAssertFalse(app.buttons["figure-plugin-button"].exists)
        let toggle = app.buttons["figure-artifact-sidebar-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 4))
        app.activate()
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let sidebar = app.descendants(matching: .any)["figure-artifact-sidebar"].firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["figure-artifact-image"].exists)
        XCTAssertTrue(app.buttons["export-figure-button"].exists)

        let resizeHandle = app.descendants(matching: .any)["figure-artifact-sidebar-resize-handle"].firstMatch
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 4))
        let originalWidth = sidebar.frame.width
        let canGrow = originalWidth + 100 < app.windows.firstMatch.frame.width - 238 - 360
        let dragDistance: CGFloat = canGrow ? -100 : 100
        let dragStart = resizeHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        app.activate()
        dragStart.press(
            forDuration: 0.1,
            thenDragTo: dragStart.withOffset(CGVector(dx: dragDistance, dy: 0))
        )
        let resizedWidth = sidebar.frame.width
        XCTAssertGreaterThan(abs(resizedWidth - originalWidth), 60)

        let restoreStart = resizeHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        restoreStart.press(
            forDuration: 0.1,
            thenDragTo: restoreStart.withOffset(CGVector(dx: -dragDistance, dy: 0))
        )

        app.buttons["知识库"].click()
        XCTAssertTrue(app.descendants(matching: .any)["figure-artifact-sidebar"].exists)
    }

    @MainActor
    func testAgentActivityButtonTogglesDrawer() {
        let app = launchApp(language: "zh-Hans")

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        app.buttons["会话"].click()
        app.activate()

        let activityButton = app.buttons["agent-activity-toggle"]
        let activityPanel = app.descendants(matching: .any)["agent-activity-panel"].firstMatch
        XCTAssertTrue(activityButton.waitForExistence(timeout: 4))
        XCTAssertEqual(activityButton.label, "智能体活动")
        let wasVisible = activityPanel.exists

        app.activate()
        activityButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        waitForExistence(!wasVisible, of: activityPanel)

        app.activate()
        activityButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        waitForExistence(wasVisible, of: activityPanel)
    }

    @MainActor
    func testKnowledgeLibrarySwitchesScopesAndShowsFilesAndSize() throws {
        let project = dataRoot.appendingPathComponent("ResearchProject")
        try prepareKnowledgeInventory(kind: "project", root: project.appendingPathComponent(".pi/knowledge"), count: 2)
        try prepareKnowledgeInventory(kind: "global", root: dataRoot.appendingPathComponent("knowledge"), count: 1)
        let app = launchApp(language: "zh-Hans", projectRoot: project)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        let projectEntry = app.buttons["sidebar-knowledge-project"]
        XCTAssertTrue(projectEntry.waitForExistence(timeout: 4))
        projectEntry.click()
        XCTAssertTrue(app.staticTexts["knowledge-heading"].waitForExistence(timeout: 4))
        let count = app.descendants(matching: .any)["knowledge-file-count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 8))
        let projectCount = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '2'"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [projectCount], timeout: 8), .completed)
        XCTAssertTrue(app.descendants(matching: .any)["knowledge-total-size"].exists)
        XCTAssertTrue(app.buttons["knowledge-file-sources/paper-0.md"].exists)
        XCTAssertTrue(app.buttons["index-knowledge-button"].exists)
        XCTAssertTrue(app.buttons["import-knowledge-button"].exists)
        app.buttons["knowledge-file-sources/paper-0.md"].click()
        XCTAssertTrue(app.buttons["关闭"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["打开原文件"].exists)
        app.buttons["关闭"].click()
        app.buttons["knowledge-category-drafts"].click()
        XCTAssertFalse(app.buttons["knowledge-file-sources/paper-0.md"].exists)
        app.buttons["knowledge-category-all"].click()
        app.buttons["sidebar-knowledge-global"].click()
        let globalCount = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [globalCount], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["knowledge-file-sources/paper-1.md"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Knowledge library in Chinese"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func prepareKnowledgeInventory(kind: String, root: URL, count: Int) throws {
        let sources = root.appendingPathComponent("sources")
        let fixtures = dataRoot.appendingPathComponent("ui-fixtures")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        var files: [[String: Any]] = []
        for index in 0..<count {
            let name = "paper-\(index).md"
            let content = "# Study \(index)\n\nSource evidence and methods.\n"
            let data = Data(content.utf8)
            try data.write(to: sources.appendingPathComponent(name))
            files.append([
                "relativePath": "sources/\(name)", "category": "sources", "name": name,
                "extension": ".md", "sizeBytes": data.count, "modifiedAt": "2026-09-05T01:02:03.000Z",
                "supported": true, "index": NSNull(),
            ])
        }
        let bytes = files.reduce(0) { $0 + ($1["sizeBytes"] as? Int ?? 0) }
        let snapshot: [String: Any] = [
            "success": true,
            "scope": ["id": kind, "kind": kind, "knowledgeRoot": root.path,
                      "projectRoot": kind == "project" ? root.deletingLastPathComponent().deletingLastPathComponent().path as Any : NSNull(),
                      "indexPath": dataRoot.appendingPathComponent("index.sqlite").path],
            "initialized": false, "fileCount": count, "totalBytes": bytes,
            "categories": ["sources": ["files": count, "bytes": bytes]],
            "files": files, "truncated": false, "latestRun": NSNull(),
        ]
        try JSONSerialization.data(withJSONObject: snapshot).write(to: fixtures.appendingPathComponent("inventory-\(kind).json"))
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
    private func launchApp(language: String, projectRoot: URL? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PERSONAL_PI_UI_TESTING"] = "1"
        app.launchEnvironment["PERSONAL_PI_DATA_ROOT"] = dataRoot.path
        if let projectRoot { app.launchEnvironment["PERSONAL_PI_UI_PROJECT_ROOT"] = projectRoot.path }
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
            "kind": "figure",
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

    private func waitForExistence(_ expected: Bool, of element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == %@", NSNumber(value: expected)),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 4), .completed)
    }

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
