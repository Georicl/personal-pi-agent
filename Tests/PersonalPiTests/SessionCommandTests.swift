import Foundation
import Testing
@testable import PersonalPi

@Suite("Pi session commands")
struct SessionCommandTests {
    @Test("Tool turns and retry boundaries do not finish a user task")
    func preservesRunAcrossTurns() {
        var lifecycle = PiRunLifecycle()
        lifecycle.receive("agent_start")
        for event in ["tool_execution_start", "tool_execution_end", "turn_end", "agent_end", "extension_error"] {
            lifecycle.receive(event)
            #expect(lifecycle.isActive)
        }
        lifecycle.receive("extension_ui_request")
        #expect(lifecycle.phase == .waiting)
        lifecycle.receive("turn_start")
        #expect(lifecycle.phase == .running)
        lifecycle.receive("agent_settled")
        #expect(!lifecycle.isActive)
        lifecycle.receive("agent_start")
        lifecycle.receive("disconnected")
        #expect(!lifecycle.isActive)
    }

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

    @Test("Pi launches the bundled Figure package from its plugin manifest")
    func includesFigurePluginPackage() throws {
        let plugin = try #require(PiLaunchConfiguration.figurePlugin)
        let arguments = PiLaunchConfiguration.arguments(projectTrusted: true)

        #expect(plugin.manifest.id == "figure")
        #expect(plugin.manifest.command == "figure")
        #expect(plugin.manifest.settingsNamespace == "figure")
        #expect(plugin.manifest.artifacts.contains { $0.kind == "figure" && $0.renderer == "figure" })
        #expect(FileManager.default.fileExists(atPath: plugin.rootURL.appendingPathComponent("package.json").path))
        #expect(FileManager.default.fileExists(atPath: plugin.rootURL.appendingPathComponent("extensions/index.js").path))
        #expect(FileManager.default.fileExists(atPath: plugin.rootURL.appendingPathComponent("skills/figure/SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: plugin.rootURL.appendingPathComponent("runtime/runner.py").path))
        #expect(arguments.containsSubsequence(["--extension", plugin.rootURL.path]))
    }

    @Test("Pi launches the bundled Knowledge package from its plugin manifest")
    func includesKnowledgePluginPackage() throws {
        let plugin = try #require(PiLaunchConfiguration.knowledgePlugin)
        let arguments = PiLaunchConfiguration.arguments(projectTrusted: true)

        #expect(plugin.manifest.id == "knowledge")
        #expect(plugin.manifest.command == "knowledge")
        #expect(plugin.manifest.settingsNamespace == "knowledge")
        #expect(plugin.manifest.artifacts.isEmpty)
        #expect(FileManager.default.fileExists(atPath: plugin.rootURL.appendingPathComponent("package.json").path))
        #expect(FileManager.default.fileExists(atPath: plugin.rootURL.appendingPathComponent("extensions/index.js").path))
        #expect(FileManager.default.fileExists(atPath: plugin.rootURL.appendingPathComponent("skills/knowledge/SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: plugin.rootURL.appendingPathComponent("runtime/knowledge_core.py").path))
        #expect(arguments.containsSubsequence(["--extension", plugin.rootURL.path]))
    }
}

@Suite("RPC connection lifecycle")
@MainActor
struct RPCConnectionTests {
    private func makeClient() -> PiRPCClient {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/rpc_peer.py")
        return PiRPCClient(executable: "/usr/bin/python3", arguments: ["-u", fixture.path],
                           startupTimeout: 5, requestTimeout: 0.15, newSessionTimeout: 0.2)
    }

    private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<1000 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate(), "RPC callback did not complete")
    }

    @Test("A cancelled startup cannot time out the replacement connection")
    func isolatesRestarts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = makeClient()
        defer { client.stop() }
        var first: [Bool] = []
        var second: [Bool] = []
        client.start(workingDirectory: root.appendingPathComponent("slow").path) { ok, _ in first.append(ok) }
        try await Task.sleep(for: .milliseconds(200))
        client.stop()
        client.start(workingDirectory: root.appendingPathComponent("slow").path) { ok, message in
            #expect(ok, "Replacement startup: \(message)")
            second.append(ok)
        }
        try await waitFor { !second.isEmpty }
        // Hosted macOS runners can spend seconds cold-starting system Python.
        // Use the production launch budget, then cross the cancelled deadline.
        try await Task.sleep(for: .seconds(5))
        #expect(first == [false])
        #expect(second == [true])
        #expect(client.processIdentifier != nil)
        #expect(client.pendingRequestCount == 0)
    }

    @Test("Requests finish on timeout, stop and disconnected send without leaking callbacks")
    func completesPendingRequests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = makeClient()
        defer { client.stop() }
        var connected = false
        client.start(workingDirectory: root.path) { ok, message in
            #expect(ok, "Startup: \(message)")
            connected = ok
        }
        try await waitFor { connected }
        var messages = 0
        client.requestMessages { _ in messages += 1 }
        try await waitFor { messages == 1 }
        #expect(client.pendingRequestCount == 0)
        var newSession: [Bool] = []
        client.newSession(workingDirectory: root.path) { newSession.append($0) }
        client.requestMessages { _ in messages += 1 }
        client.stop()
        #expect(messages == 2)
        #expect(newSession == [false])
        client.requestMessages { _ in messages += 1 }
        #expect(messages == 3)
        try await Task.sleep(for: .milliseconds(300))
        #expect(client.processIdentifier == nil) // Cancelled new_session must not restart.
        #expect(client.pendingRequestCount == 0)
    }

    @Test("Unexpected process exit completes pending requests and reports termination")
    func handlesExit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = makeClient()
        defer { client.stop() }
        var connected = false
        var terminated = false
        var completed = false
        client.onTermination = { _ in terminated = true }
        client.start(workingDirectory: root.appendingPathComponent("exit").path) { ok, message in
            #expect(ok, "Startup: \(message)")
            connected = ok
        }
        try await waitFor { connected }
        client.requestMessages { _ in completed = true }
        try await waitFor { terminated && completed }
        #expect(client.processIdentifier == nil)
        #expect(client.pendingRequestCount == 0)
    }

    @Test("RPC pipe back-pressure does not block MainActor")
    func nonblockingWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = makeClient()
        defer { client.stop() }
        var connected = false
        client.start(workingDirectory: root.appendingPathComponent("blocked").path) { ok, _ in connected = ok }
        try await waitFor { connected }
        let start = ContinuousClock.now
        client.sendPrompt(String(repeating: "x", count: 1_000_000))
        #expect(start.duration(to: .now) < .seconds(1))
        client.stop()
        #expect(client.pendingRequestCount == 0)
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
