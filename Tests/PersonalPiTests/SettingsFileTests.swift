import Foundation
import Testing
@testable import PersonalPi

@Suite("Pi settings files")
struct SettingsFileTests {
    @Test("Nested project values override without deleting sibling keys")
    func nestedMergePreservesSiblings() {
        let global: [String: Any] = [
            "theme": "dark",
            "compaction": ["enabled": true, "reserveTokens": 16_384]
        ]
        let project: [String: Any] = [
            "compaction": ["reserveTokens": 8_192]
        ]

        let merged = PiSettingsFile.merge(global, project)
        let compaction = merged["compaction"] as? [String: Any]

        #expect(merged["theme"] as? String == "dark")
        #expect(compaction?["enabled"] as? Bool == true)
        #expect((compaction?["reserveTokens"] as? NSNumber)?.intValue == 8_192)
    }

    @Test("Atomic round trip preserves unknown JSON keys")
    func roundTripPreservesUnknownKeys() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let original: [String: Any] = [
            "defaultProvider": "openai-codex",
            "futureSetting": ["enabled": true]
        ]
        try PiSettingsFile.write(original, to: file)
        let loaded = try PiSettingsFile.read(file)

        #expect(loaded["defaultProvider"] as? String == "openai-codex")
        #expect((loaded["futureSetting"] as? [String: Any])?["enabled"] as? Bool == true)
    }

    @Test(arguments: ["", "0", "3", "60000"])
    func acceptsOptionalNonnegativeIntegers(_ value: String) {
        #expect(PiSettingsFile.isOptionalNonnegativeInteger(value))
    }

    @Test(arguments: ["-1", "1.5", "abc"])
    func rejectsInvalidIntegers(_ value: String) {
        #expect(!PiSettingsFile.isOptionalNonnegativeInteger(value))
    }
}
