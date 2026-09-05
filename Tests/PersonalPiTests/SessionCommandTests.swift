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

@Suite("GUI workflow boundaries")
@MainActor
struct WorkflowBoundaryTests {
    private func makeApp(_ root: URL, newSessionTimeout: TimeInterval = 2) throws -> AppState {
        let project = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/workflow_peer.py")
        let client = PiRPCClient(executable: "/usr/bin/python3", arguments: ["-u", fixture.path, root.path],
                                 newSessionTimeout: newSessionTimeout)
        return AppState(client: client,
                        runtimeContext: PiRuntimeContext(environment: [:], dataRoot: root.appendingPathComponent("pi")),
                        workspacePaths: [project.path], refreshAccounts: false)
    }

    private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<1000 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate(), "Workflow did not reach its expected state")
    }

    private func savedSession(_ root: URL, id: String, cwd: String) throws -> PiSavedSession {
        try FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("\(id).jsonl")
        let data = try JSONSerialization.data(withJSONObject: ["type": "session", "version": 3, "id": id, "cwd": cwd])
        try data.write(to: path)
        return PiSavedSession(id: id, path: path.path, timestamp: Date(), cwd: cwd)
    }

    @Test("Installed Pi RPC preserves project scope, native vetoes and nonblocking command completion",
          .enabled(if: ProcessInfo.processInfo.environment["PERSONAL_PI_TEST_NATIVE_RPC"] == "1"))
    func nativeRuntimeContract() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let runtime = PiRuntimeContext(environment: [:], dataRoot: root.appendingPathComponent("pi"))
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/workflow_extension.js")
        let client = PiRPCClient(arguments: PiLaunchConfiguration.arguments(projectTrusted: true)
            + ["--offline", "--extension", fixture.path],
            environment: runtime.processEnvironment(PiLaunchConfiguration.processEnvironment()),
            newSessionTimeout: 0.2)
        defer { client.stop() }
        let app = AppState(client: client, runtimeContext: runtime, workspacePaths: [project.path], refreshAccounts: false)
        app.connectPi()
        try await waitFor { app.sessionId != nil }
        let originalID = app.sessionId
        let saved = try savedSession(root, id: "native-B", cwd: root.appendingPathComponent("B").path)
        try Data().write(to: runtime.piRoot.appendingPathComponent("veto-next"))
        app.switchSession(saved)
        try await waitFor { !app.isSessionTransitioning }
        #expect(app.sessionId == originalID)
        #expect(app.agentStatus == "Session switch cancelled")
        try FileManager.default.removeItem(at: runtime.piRoot.appendingPathComponent("veto-next"))
        app.switchSession(saved)
        try await waitFor { app.sessionId == "native-B" }
        app.composerText = "/__workflow_context"
        app.sendPrompt()
        try await waitFor { !app.isGenerating }
        let notice = try #require(app.activities.last { $0.toolName == "Notification" })
        let paths = try #require(JSONSerialization.jsonObject(with: Data(notice.detail.utf8)) as? [String: String])
        for key in ["cwd", "sessionCwd"] {
            let actual = try #require(paths[key])
            #expect(URL(fileURLWithPath: actual).resolvingSymlinksInPath().path == app.activeWorkingDirectory)
        }
        #expect(app.knowledgeStore.projectRoot?.path == app.activeWorkingDirectory)
        #expect(app.uiRequest == nil)
        #expect(app.taskStore.tasks.isEmpty)
        // A slow interactive hook must not trigger new_session's idle fallback.
        try Data().write(to: runtime.piRoot.appendingPathComponent("ask-next"))
        let pid = client.processIdentifier
        app.startNewSession()
        try await waitFor { app.uiRequest != nil }
        try await Task.sleep(for: .milliseconds(500))
        #expect(app.isSessionTransitioning)
        #expect(client.processIdentifier == pid)
        app.respondToUIRequest(confirmed: false)
        try await waitFor { !app.isSessionTransitioning }
        #expect(app.sessionId == "native-B")
        #expect(app.agentStatus == "Session creation cancelled")
        #expect(client.processIdentifier == pid)
        #expect(!app.isGenerating)
    }

    @Test("Late veto acknowledgement cannot restart an interactive new-session operation")
    func delayedSessionVeto() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root, newSessionTimeout: 0.1)
        defer { app.piClient.stop() }
        app.connectPi()
        try await waitFor { app.sessionId != nil }
        let session = app.sessionId
        let pid = app.piClient.processIdentifier
        try Data().write(to: root.appendingPathComponent("ask-new"))
        app.startNewSession()
        try await waitFor { app.uiRequest != nil }
        try await Task.sleep(for: .milliseconds(200))
        #expect(app.isSessionTransitioning)
        app.respondToUIRequest(confirmed: false)
        try await waitFor { !app.isSessionTransitioning }
        #expect(app.agentStatus == "Session creation cancelled")
        #expect(app.sessionId == session)
        #expect(app.piClient.processIdentifier == pid)
        #expect(!app.isGenerating)
    }

    @Test("Connecting prompts stay in their original project, including restored drafts")
    func pendingPromptScope() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root)
        defer { app.piClient.stop() }
        let original = app.workspace
        app.composerText = "Intended for A"
        app.sendPrompt()
        app.selectWorkspace(PiWorkspaceInspector.placeholder(path: root.appendingPathComponent("B").path))
        try await waitFor { app.isPiRunning }
        try await Task.sleep(for: .milliseconds(350))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("prompts.jsonl").path))
        #expect(app.composerText.isEmpty)
        #expect(app.knowledgeStore.projectName == "B")
        app.selectWorkspace(original)
        #expect(app.composerText == "Intended for A")
        try await waitFor { app.isPiRunning }
        app.sendPrompt()
        try await waitFor { !app.taskStore.tasks.isEmpty }
        try await Task.sleep(for: .milliseconds(200))
        let log = try String(contentsOf: root.appendingPathComponent("prompts.jsonl"), encoding: .utf8)
        #expect(log.contains("Intended for A"))
        #expect(!log.contains("/B\""))
    }

    @Test("Restoring another project's session adopts its exact cwd and ignores old replies")
    func sessionContext() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root)
        defer { app.piClient.stop() }
        app.connectPi()
        try await waitFor { app.sessionId != nil }
        let session = try savedSession(root, id: "session-B", cwd: root.appendingPathComponent("B/nested").path)
        app.switchSession(session)
        app.composerText = "Do not send during transition"
        app.sendPrompt()
        #expect(app.composerText == "Do not send during transition")
        try await waitFor { app.sessionId == "session-B" }
        let canonical = URL(fileURLWithPath: session.cwd).resolvingSymlinksInPath().path
        #expect(app.activeWorkingDirectory == canonical)
        #expect(app.currentProjectPath == canonical)
        #expect(app.knowledgeStore.projectRoot?.path == canonical)
        try await Task.sleep(for: .milliseconds(500))
        #expect(app.messages.map { URL(fileURLWithPath: $0.text).resolvingSymlinksInPath().path } == [canonical])
        app.startNewSession()
        try await waitFor { app.sessionId == "new-nested" }
        #expect(app.activeWorkingDirectory == canonical)
        let chat = try savedSession(root, id: "chat", cwd: app.globalChatDirectory)
        app.switchSession(chat)
        try await waitFor { app.sessionId == "chat" }
        #expect(app.workspaceScope == .global)
        #expect(app.knowledgeStore.projectRoot == nil)
        #expect(app.currentProjectPath == URL(fileURLWithPath: app.globalChatDirectory).resolvingSymlinksInPath().path)
    }

    @Test("Pi session veto preserves the old session, project and process")
    func sessionCancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root)
        defer { app.piClient.stop() }
        app.connectPi()
        try await waitFor { app.sessionId != nil }
        try await Task.sleep(for: .milliseconds(400))
        let oldID = app.sessionId
        let oldMessages = app.messages.map(\.text)
        let oldPID = app.piClient.processIdentifier
        let veto = try savedSession(root, id: "veto", cwd: root.appendingPathComponent("B").path)
        app.switchSession(veto)
        try await waitFor { !app.isSessionTransitioning }
        #expect(app.agentStatus == "Session switch cancelled")
        #expect(app.sessionId == oldID)
        #expect(app.knowledgeStore.projectName == "A")
        try Data().write(to: root.appendingPathComponent("veto-new"))
        app.startNewSession()
        try await waitFor { !app.isSessionTransitioning }
        #expect(app.agentStatus == "Session creation cancelled")
        #expect(app.sessionId == oldID)
        #expect(app.messages.map(\.text) == oldMessages)
        #expect(app.piClient.processIdentifier == oldPID)
    }

    @Test("Notifications and pure commands do not create model tasks or wait for input")
    func commandCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root)
        defer { app.piClient.stop() }
        app.connectPi()
        try await waitFor { app.sessionId != nil }
        app.composerText = "/notify"
        app.sendPrompt()
        try await waitFor { !app.isGenerating }
        #expect(app.uiRequest == nil)
        #expect(app.taskStore.tasks.isEmpty)
        #expect(app.activities.contains { $0.detail == "Status available" })
        app.composerText = "/ask"
        app.sendPrompt()
        try await waitFor { app.uiRequest != nil }
        #expect(app.isGenerating)
        #expect(app.taskStore.tasks.isEmpty)
        app.composerText = "/notify"
        app.sendPrompt()
        #expect(app.composerText == "/notify") // Do not replace an outstanding command's completion callback.
        app.respondToUIRequest(cancelled: true)
        try await waitFor { !app.isGenerating }
        #expect(app.agentStatus == "Cancelled")
        #expect(app.taskStore.tasks.isEmpty)
    }

    @Test("Commands that queue model work finish only on agent_settled; cancellation stays cancelled")
    func modelCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root)
        defer { app.piClient.stop() }
        app.connectPi()
        try await waitFor { app.sessionId != nil }
        app.composerText = "/queue-model"
        app.sendPrompt()
        try await Task.sleep(for: .milliseconds(200))
        #expect(app.isGenerating) // idle model + pendingMessageCount=1 is not complete.
        try await waitFor { app.taskStore.tasks.first?.state == .running }
        try await waitFor { !app.isGenerating }
        #expect(app.taskStore.tasks.count == 1)
        #expect(app.taskStore.tasks.first?.detail == "Completed")
        app.composerText = "/hold"
        app.sendPrompt()
        try await waitFor { app.taskStore.tasks.first?.state == .running }
        app.stopGeneration()
        try await waitFor { !app.isGenerating }
        #expect(app.taskStore.tasks.count == 1)
        #expect(app.taskStore.tasks.first?.detail == "Cancelled")
        app.composerText = "/notify"
        app.sendPrompt()
        try await waitFor { !app.isGenerating }
        #expect(app.taskStore.tasks.first?.detail == "Cancelled")
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
        // Cancel on this MainActor turn, before the startup reply can run. A
        // 200ms sleep is not a deadline: under CI load it can resume after the
        // peer's 350ms successful response and test a different scenario.
        #expect(first.isEmpty)
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
        var newSession: [PiSessionChangeResult] = []
        client.newSession(workingDirectory: root.path) { newSession.append($0) }
        client.requestMessages { _ in messages += 1 }
        client.stop()
        #expect(messages == 2)
        #expect(newSession == [.cancelled])
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
