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

    @Test("Per-model thinking overrides are written and can be cleared")
    func writesStringDictionary() {
        var document: [String: Any] = ["futureSetting": true]

        PiSettingsFile.setStringDictionary(
            ["openai-codex/gpt-5.6": "high"],
            key: "modelThinkingLevels",
            in: &document
        )
        #expect((document["modelThinkingLevels"] as? [String: String])?["openai-codex/gpt-5.6"] == "high")

        PiSettingsFile.setStringDictionary([:], key: "modelThinkingLevels", in: &document)
        #expect(document["modelThinkingLevels"] == nil)
        #expect(document["futureSetting"] as? Bool == true)
    }

    @Test("Thinking levels follow Pi model capability metadata")
    func derivesSupportedThinkingLevels() {
        #expect(PiModelOption.thinkingLevels(reasoning: false, thinkingLevelMap: nil) == ["off"])
        #expect(PiModelOption.thinkingLevels(reasoning: true, thinkingLevelMap: nil) == [
            "off", "minimal", "low", "medium", "high"
        ])
        #expect(PiModelOption.thinkingLevels(
            reasoning: true,
            thinkingLevelMap: ["xhigh": NSNull(), "max": "max"]
        ) == ["off", "minimal", "low", "medium", "high", "max"])
    }

    @Test("Full Pi model metadata is decoded for GUI model controls")
    func decodesModelMetadata() throws {
        let model = try #require(PiModelOption.decode([
            "provider": "openai-codex",
            "id": "gpt-5.6",
            "name": "GPT-5.6",
            "reasoning": true,
            "thinkingLevelMap": ["xhigh": "xhigh", "max": "max"]
        ]))

        #expect(model.identity == "openai-codex/gpt-5.6")
        #expect(model.supportedThinkingLevels.contains("max"))
    }

    @Test("Advanced runtime settings preserve Pi nested key shapes")
    func writesAdvancedRuntimeSettings() {
        var document: [String: Any] = ["futureSetting": true]

        PiSettingsFile.setString("http://127.0.0.1:7890", key: "httpProxy", in: &document)
        PiSettingsFile.setOptionalInt("45000", path: ["httpIdleTimeoutMs"], in: &document)
        PiSettingsFile.setOptionalInt("120000", path: ["retry", "provider", "timeoutMs"], in: &document)
        PiSettingsFile.setOptionalInt("5", path: ["retry", "provider", "maxRetries"], in: &document)
        PiSettingsFile.setString("~/Library/Application Support/Pi Sessions", key: "sessionDir", in: &document)
        PiSettingsFile.setStringList("pnpm\n--silent", key: "npmCommand", in: &document)
        PiSettingsFile.setOptionalBool(.enabled, path: ["branchSummary", "skipPrompt"], in: &document)
        PiSettingsFile.setOptionalBool(.disabled, path: ["warnings", "anthropicExtraUsage"], in: &document)
        PiSettingsFile.setValue("/opt/project/.venv/bin/python", path: ["scientificFigure", "pythonPath"], in: &document)
        PiSettingsFile.setOptionalBool(.disabled, path: ["scientificFigure", "keepWorkFiles"], in: &document)

        #expect(document["httpProxy"] as? String == "http://127.0.0.1:7890")
        #expect((document["httpIdleTimeoutMs"] as? NSNumber)?.intValue == 45000)
        #expect((PiSettingsFile.value(in: document, path: ["retry", "provider", "timeoutMs"]) as? NSNumber)?.intValue == 120000)
        #expect((PiSettingsFile.value(in: document, path: ["retry", "provider", "maxRetries"]) as? NSNumber)?.intValue == 5)
        #expect(document["sessionDir"] as? String == "~/Library/Application Support/Pi Sessions")
        #expect(document["npmCommand"] as? [String] == ["pnpm", "--silent"])
        #expect(PiSettingsFile.value(in: document, path: ["branchSummary", "skipPrompt"]) as? Bool == true)
        #expect(PiSettingsFile.value(in: document, path: ["warnings", "anthropicExtraUsage"]) as? Bool == false)
        #expect(PiSettingsFile.value(in: document, path: ["scientificFigure", "pythonPath"]) as? String == "/opt/project/.venv/bin/python")
        #expect(PiSettingsFile.value(in: document, path: ["scientificFigure", "keepWorkFiles"]) as? Bool == false)
        #expect(document["futureSetting"] as? Bool == true)
    }
}
