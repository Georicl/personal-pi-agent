import Foundation
import Testing
@testable import PersonalPi

@Suite("Workspace and language")
struct WorkspaceAndLanguageTests {
    @Test("Workspace containment respects path boundaries")
    func workspaceContainment() {
        #expect(PiWorkspaceInspector.isInside("/tmp/project", root: "/tmp/project"))
        #expect(PiWorkspaceInspector.isInside("/tmp/project/subdir", root: "/tmp/project"))
        #expect(!PiWorkspaceInspector.isInside("/tmp/project-copy", root: "/tmp/project"))
    }

    @Test("Language choices expose stable locale identifiers")
    func languageLocales() {
        #expect(AppLanguage.english.locale.identifier == "en")
        #expect(AppLanguage.simplifiedChinese.locale.identifier == "zh-Hans")
    }

    @Test("Session roots include Pi defaults plus effective Global and Project settings")
    func sessionDirectoryRoots() throws {
        let fixture = try SessionDirectoryFixture()
        defer { fixture.remove() }
        let project = fixture.root.appendingPathComponent("project", isDirectory: true)
        let inheritedProject = fixture.root.appendingPathComponent("inherited", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inheritedProject, withIntermediateDirectories: true)
        try PiSettingsFile.write(
            ["sessionDir": "~/Pi Sessions"],
            to: fixture.piRoot.appendingPathComponent("agent/settings.json")
        )
        try PiSettingsFile.write(
            ["sessionDir": ".pi/project-sessions"],
            to: project.appendingPathComponent(".pi/settings.json")
        )

        let roots = PiSessionDirectoryResolver.scanRoots(
            piRoot: fixture.piRoot,
            globalChatDirectory: fixture.globalChat.path,
            projectPaths: [project.path, inheritedProject.path],
            environmentSessionDirectory: nil,
            homeDirectory: fixture.home.path
        ).map(\.path)

        #expect(roots == [
            fixture.piRoot.appendingPathComponent("agent/sessions").path,
            fixture.home.appendingPathComponent("Pi Sessions").path,
            project.appendingPathComponent(".pi/project-sessions").path
        ])
    }

    @Test("Environment session directory overrides settings relative to each Pi cwd")
    func environmentSessionDirectoryOverride() throws {
        let fixture = try SessionDirectoryFixture()
        defer { fixture.remove() }
        let project = fixture.root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try PiSettingsFile.write(
            ["sessionDir": "~/ignored"],
            to: fixture.piRoot.appendingPathComponent("agent/settings.json")
        )

        let roots = PiSessionDirectoryResolver.scanRoots(
            piRoot: fixture.piRoot,
            globalChatDirectory: fixture.globalChat.path,
            projectPaths: [project.path],
            environmentSessionDirectory: "relative-sessions",
            homeDirectory: fixture.home.path
        ).map(\.path)

        #expect(roots == [
            fixture.piRoot.appendingPathComponent("agent/sessions").path,
            fixture.globalChat.appendingPathComponent("relative-sessions").path,
            project.appendingPathComponent("relative-sessions").path
        ])
    }

    @Test("Session catalog combines configured roots and removes overlapping duplicates")
    func sessionCatalogMultipleRoots() throws {
        let fixture = try SessionDirectoryFixture()
        defer { fixture.remove() }
        let defaultRoot = fixture.piRoot.appendingPathComponent("agent/sessions", isDirectory: true)
        let nestedDefaultRoot = defaultRoot.appendingPathComponent("--project--", isDirectory: true)
        let customRoot = fixture.root.appendingPathComponent("custom-sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDefaultRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: customRoot, withIntermediateDirectories: true)
        try sessionHeader(id: "default", cwd: "/tmp/default", timestamp: "2026-09-03T10:00:00.000Z")
            .write(to: nestedDefaultRoot.appendingPathComponent("default.jsonl"), atomically: true, encoding: .utf8)
        try sessionHeader(id: "custom", cwd: "/tmp/custom", timestamp: "2026-09-03T11:00:00.000Z")
            .write(to: customRoot.appendingPathComponent("custom.jsonl"), atomically: true, encoding: .utf8)

        let sessions = PiSessionCatalog.allSessions(at: [defaultRoot, nestedDefaultRoot, customRoot])

        #expect(sessions.map(\.id) == ["custom", "default"])
        #expect(Set(sessions.map(\.path)).count == 2)
    }

    private func sessionHeader(id: String, cwd: String, timestamp: String) -> String {
        "{\"type\":\"session\",\"id\":\"\(id)\",\"cwd\":\"\(cwd)\",\"timestamp\":\"\(timestamp)\"}\n"
    }
}

private struct SessionDirectoryFixture {
    let root: URL
    let home: URL
    let piRoot: URL
    let globalChat: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalPiSessionDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        piRoot = home.appendingPathComponent(".pi", isDirectory: true)
        globalChat = piRoot.appendingPathComponent("chat", isDirectory: true)
        try FileManager.default.createDirectory(at: globalChat, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
