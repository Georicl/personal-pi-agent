import Foundation
import Testing
@testable import PersonalPi

@Suite("Runtime services")
struct RuntimeServicesTests {
    @Test("GUI and child processes share default and overridden Pi paths")
    func pathContract() {
        let home = URL(fileURLWithPath: "/tmp/test-home")
        let standard = PiRuntimeContext(environment: [:], home: home)
        #expect(standard.piRoot.path == "/tmp/test-home/.pi")
        #expect(standard.agentDirectory.path == "/tmp/test-home/.pi/agent")
        let custom = PiRuntimeContext(environment: ["PI_CODING_AGENT_DIR": "~/portable/runtime"], home: home)
        #expect(custom.piRoot.path == "/tmp/test-home/portable")
        #expect(custom.settingsURL.path == "/tmp/test-home/portable/runtime/settings.json")
        let separate = PiRuntimeContext(environment: ["PERSONAL_PI_DATA_ROOT": "/tmp/data", "PI_CODING_AGENT_DIR": "/tmp/auth/runtime",
            "PERSONAL_PI_KNOWLEDGE_ENVIRONMENT": "~/python"], home: home)
        #expect(separate.piRoot.path == "/tmp/data")
        #expect(separate.agentDirectory.path == "/tmp/auth/runtime")
        #expect(separate.knowledgeEnvironment.path == "/tmp/test-home/python")
        let exported = separate.processEnvironment(["PATH": "/bin"])
        #expect(exported["PERSONAL_PI_DATA_ROOT"] == "/tmp/data")
        #expect(exported["PI_CODING_AGENT_DIR"] == "/tmp/auth/runtime")
        #expect(exported["PATH"] == "/bin")
        #expect(PiRuntimeContext(environment: exported, home: home) == separate)
    }

    @Test("Both output streams drain concurrently, without deadlocking on pipe capacity")
    func processCapture() async throws {
        let result = try await Task.detached {
            try PiProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: ["-c", "import sys; sys.stderr.write('e'*200000); sys.stdout.write('o'*200000)"],
                workingDirectory: FileManager.default.temporaryDirectory,
                environment: ProcessInfo.processInfo.environment, timeout: 5)
        }.value
        #expect(result.status == 0)
        #expect(result.output.count == 200_000)
        #expect(result.error.count == 200_000)
    }

    @Test("Timeout works even when the child does not read a large stdin payload")
    func processTimeout() async {
        let timedOut = await Task.detached {
            do {
                _ = try PiProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"],
                    workingDirectory: FileManager.default.temporaryDirectory, environment: [:],
                    input: Data(repeating: 42, count: 1_000_000), timeout: 0.1)
                return false
            } catch PiProcessError.timedOut { return true }
            catch { return false }
        }.value
        #expect(timedOut)
    }

    @Test("Oversized subprocess output is an explicit error, not truncated JSON")
    func outputLimit() async {
        let rejected = await Task.detached {
            do {
                _ = try PiProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                    arguments: ["-c", "print('x'*100000)"], workingDirectory: FileManager.default.temporaryDirectory,
                    environment: ProcessInfo.processInfo.environment, timeout: 5, outputLimit: 1024)
                return false
            } catch PiProcessError.outputTooLarge { return true }
            catch { return false }
        }.value
        #expect(rejected)
    }

    @Test("Session coordinator owns run state and invalidates old connection identities")
    @MainActor
    func sessionState() {
        let coordinator = PiSessionCoordinator()
        let old = coordinator.beginConnection()
        #expect(coordinator.connectionState == .connecting)
        coordinator.receive("agent_start")
        coordinator.receive("turn_end")
        #expect(coordinator.isGenerating)
        coordinator.invalidateConnection()
        #expect(old != coordinator.revision)
        coordinator.receive("disconnected")
        #expect(!coordinator.isGenerating)
    }

    @Test("Settings editor preserves scope, unknown keys and read-only effective previews")
    @MainActor
    func settingsEditor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let global = root.appendingPathComponent("global.json")
        let project = root.appendingPathComponent("project.json")
        try PiSettingsFile.write(["defaultProvider": "global-provider", "httpProxy": "http://localhost:8080"], to: global)
        try PiSettingsFile.write(["defaultModel": "old", "custom": ["preserve": true]], to: project)
        let editor = PiSettingsEditor()
        editor.configure(globalURL: global, projectURL: project)
        editor.load()
        editor.model = "new"
        editor.retryCount = "-1"
        #expect(!editor.save())
        #expect(try PiSettingsFile.read(project)["defaultModel"] as? String == "old")
        editor.retryCount = "3"
        #expect(editor.save())
        let saved = try PiSettingsFile.read(project)
        #expect(saved["defaultModel"] as? String == "new")
        #expect((saved["custom"] as? [String: Bool])?["preserve"] == true)
        #expect(saved["httpProxy"] == nil)
        editor.selectedScope = .effective
        editor.load()
        #expect(editor.provider == "global-provider")
        #expect(!editor.save())
        let oldContext = editor.contextID
        editor.configure(globalURL: global, projectURL: nil)
        editor.load()
        #expect(editor.contextID != oldContext)
        #expect(editor.selectedScope == .global)
    }
}
