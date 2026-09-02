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
}
