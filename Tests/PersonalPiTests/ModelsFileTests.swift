import Foundation
import Testing
@testable import PersonalPi

@Suite("Pi custom model providers")
struct ModelsFileTests {
    @Test("Environment credentials are stored as references, not secret values")
    func environmentCredentialReference() throws {
        var draft = exampleDraft()
        draft.credentialSource = .environment
        draft.environmentVariable = "${RESEARCH_MODEL_API_KEY}"
        draft.reasoning = true
        draft.supportsImages = true
        draft.authHeader = true
        draft.contextWindow = "200000"
        draft.maxTokens = "16384"

        let provider = try draft.providerDocument()
        let models = try #require(provider["models"] as? [[String: Any]])
        let model = try #require(models.first)

        #expect(provider["apiKey"] as? String == "$RESEARCH_MODEL_API_KEY")
        #expect(provider["baseUrl"] as? String == "https://models.example.test/v1")
        #expect(provider["authHeader"] as? Bool == true)
        #expect(model["id"] as? String == "research-model")
        #expect(model["reasoning"] as? Bool == true)
        #expect(model["input"] as? [String] == ["text", "image"])
        #expect((model["contextWindow"] as? NSNumber)?.intValue == 200_000)
        #expect((model["maxTokens"] as? NSNumber)?.intValue == 16_384)
    }

    @Test("Pi login mode never writes an API key field")
    func piLoginOmitsAPIKey() throws {
        let provider = try exampleDraft().providerDocument()
        #expect(provider["apiKey"] == nil)
    }

    @Test("Adding a provider preserves unknown keys and existing providers")
    func addPreservesExistingConfiguration() throws {
        let directory = temporaryDirectory()
        let file = directory.appendingPathComponent("models.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let original: [String: Any] = [
            "futureOption": ["enabled": true],
            "providers": [
                "existing": [
                    "baseUrl": "http://localhost:11434/v1",
                    "api": "openai-completions",
                    "apiKey": "local",
                    "models": [["id": "local-model"]]
                ]
            ]
        ]
        try writeJSON(original, to: file)

        let summary = try PiModelsFile.add(exampleDraft(), to: file)
        let loaded = try PiModelsFile.read(file)
        let providers = try #require(loaded["providers"] as? [String: Any])

        #expect(summary == PiModelsCatalogSummary(providerCount: 2, modelCount: 2))
        #expect(providers["existing"] != nil)
        #expect(providers["research-cloud"] != nil)
        #expect((loaded["futureOption"] as? [String: Any])?["enabled"] as? Bool == true)
    }

    @Test("An existing provider is not overwritten")
    func duplicateProviderIsRejected() throws {
        let directory = temporaryDirectory()
        let file = directory.appendingPathComponent("models.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try PiModelsFile.add(exampleDraft(), to: file)

        do {
            _ = try PiModelsFile.add(exampleDraft(), to: file)
            Issue.record("Expected duplicate provider validation to fail")
        } catch let error as PiModelsFileError {
            #expect(error == .duplicateProvider)
        }

        #expect(try PiModelsFile.summary(at: file) == PiModelsCatalogSummary(providerCount: 1, modelCount: 1))
    }

    @Test("Invalid environment variable names are rejected")
    func rejectsInvalidEnvironmentVariable() {
        var draft = exampleDraft()
        draft.credentialSource = .environment
        draft.environmentVariable = "API KEY"

        do {
            _ = try draft.providerDocument()
            Issue.record("Expected environment variable validation to fail")
        } catch let error as PiModelsFileError {
            #expect(error == .invalidEnvironmentVariable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Malformed providers entries are surfaced instead of shown as empty")
    func malformedProvidersEntryIsRejected() throws {
        let directory = temporaryDirectory()
        let file = directory.appendingPathComponent("models.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeJSON(["providers": ["not", "an", "object"]], to: file)

        do {
            _ = try PiModelsFile.summary(at: file)
            Issue.record("Expected malformed providers validation to fail")
        } catch let error as PiModelsFileError {
            #expect(error == .invalidProviders)
        }
    }

    private func exampleDraft() -> PiCustomProviderDraft {
        PiCustomProviderDraft(
            providerID: "research-cloud",
            baseURL: "https://models.example.test/v1",
            api: .openAICompletions,
            credentialSource: .piLogin,
            environmentVariable: "",
            modelID: "research-model",
            modelName: "Research Model",
            reasoning: false,
            supportsImages: false,
            authHeader: false,
            contextWindow: "",
            maxTokens: ""
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalPiModelsTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
