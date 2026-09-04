import Foundation
import Testing
@testable import PersonalPi

@Suite("Pi session commands")
struct SessionCommandTests {
    @Test("GUI exposes the Pi session and branch command surface")
    @MainActor
    func exposesNativeCommands() {
        let names = Set(AppState.nativeCommands.map(\.name))
        #expect(names.isSuperset(of: [
            "resume", "session", "tree", "fork", "clone", "export", "copy", "reload", "compact"
        ]))
    }

    @Test("Session tree responses retain hierarchy and message identity")
    func decodesSessionTree() throws {
        let tree = try #require(PiSessionTreeNode.decode([
            "entry": [
                "id": "root-message",
                "parentId": NSNull(),
                "type": "message",
                "timestamp": "2026-09-03T12:00:00.000Z",
                "message": [
                    "role": "user",
                    "content": [["type": "text", "text": "Start here"]]
                ]
            ],
            "label": "baseline",
            "children": [[
                "entry": [
                    "id": "assistant-message",
                    "parentId": "root-message",
                    "type": "message",
                    "timestamp": "2026-09-03T12:00:01.000Z",
                    "message": [
                        "role": "assistant",
                        "content": [["type": "text", "text": "Done"]]
                    ]
                ],
                "children": []
            ]]
        ]))

        #expect(tree.id == "root-message")
        #expect(tree.label == "baseline")
        #expect(tree.isUserMessage)
        #expect(tree.text == "Start here")
        #expect(tree.timestamp != nil)
        #expect(tree.children.first?.parentId == "root-message")
        #expect(tree.children.first?.text == "Done")
    }

    @Test("Pi launches with the bundled session runtime extension")
    func includesRuntimeExtension() throws {
        let extensionURL = try #require(PiLaunchConfiguration.runtimeExtensionURL)
        #expect(FileManager.default.fileExists(atPath: extensionURL.path))

        let arguments = PiLaunchConfiguration.arguments(projectTrusted: true)
        let flagIndex = try #require(arguments.firstIndex(of: "--extension"))
        #expect(arguments.indices.contains(flagIndex + 1))
        #expect(arguments[flagIndex + 1] == extensionURL.path)
    }

    @Test("Pi launches with the scientific figure extension and skill")
    func includesScientificFigureResources() throws {
        let extensionURL = try #require(PiLaunchConfiguration.scientificFigureExtensionURL)
        let skillURL = try #require(PiLaunchConfiguration.scientificFigureSkillURL)
        let arguments = PiLaunchConfiguration.arguments(projectTrusted: true)

        #expect(arguments.containsSubsequence(["--extension", extensionURL.path]))
        #expect(arguments.containsSubsequence(["--skill", skillURL.path]))
    }
}

private extension Array where Element: Equatable {
    func containsSubsequence(_ subsequence: [Element]) -> Bool {
        guard !subsequence.isEmpty, subsequence.count <= count else { return false }
        return indices.contains { start in
            let end = index(start, offsetBy: subsequence.count, limitedBy: endIndex) ?? endIndex
            return distance(from: start, to: end) == subsequence.count
                && Array(self[start..<end]) == subsequence
        }
    }
}
