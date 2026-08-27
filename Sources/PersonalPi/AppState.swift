import Foundation
import SwiftUI
import AppKit

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case sessions
    case knowledge
    case projects
    case tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .sessions: "Sessions"
        case .knowledge: "Knowledge"
        case .projects: "Projects"
        case .tasks: "Tasks"
        }
    }

    var icon: String {
        switch self {
        case .overview: "diamond"
        case .sessions: "square.on.square"
        case .knowledge: "line.3.horizontal"
        case .projects: "tablecells"
        case .tasks: "diamond.inset.filled"
        }
    }
}

struct PiChatMessage: Identifiable, Sendable {
    let id: String
    let role: String
    var text: String
    var isStreaming: Bool

    var isUser: Bool { role == "user" }
}

struct PiUIRequest: Identifiable, Sendable {
    let id: String
    let method: String
    let title: String
    let message: String
    let options: [String]
    let placeholder: String
    let prefill: String
}

enum PiActivityState: Sendable {
    case running
    case completed
    case failed
}

struct PiActivity: Identifiable, Sendable {
    let id: String
    var toolName: String
    var detail: String
    var state: PiActivityState
    var startedAt: Date = Date()
    var endedAt: Date?

    var durationLabel: String? {
        guard state != .running else { return nil }
        let end = endedAt ?? Date()
        return PiFormat.duration(end.timeIntervalSince(startedAt))
    }
}

struct PiSavedSession: Identifiable, Sendable, Hashable {
    let id: String
    let path: String
    let timestamp: Date
    let cwd: String

    var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return "Session · \(formatter.string(from: timestamp))"
    }

    var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Unknown project" : name
    }

    var locationLabel: String {
        cwd.isEmpty ? "Project path unavailable" : cwd
    }

    var clockLabel: String {
        PiFormat.sessionClock(timestamp)
    }
}

struct PiProjectGroup: Identifiable, Sendable, Hashable {
    let id: String
    let cwd: String
    let sessions: [PiSavedSession]

    var name: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Unknown project" : name
    }

    var locationLabel: String {
        cwd.isEmpty ? "Project path unavailable" : cwd
    }

    var latestSession: PiSavedSession? {
        sessions.first
    }
}

private struct PiCatalogSnapshot: Sendable {
    let sessions: [PiSavedSession]
    let groups: [PiProjectGroup]
    let workspaces: [PiWorkspace]
}

enum PiConnectionState {
    case ready
    case connecting
    case connected
    case unavailable(String)

    var label: String {
        switch self {
        case .ready:
            return "Pi CLI ready"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Pi connected"
        case .unavailable(let message):
            if message.localizedCaseInsensitiveContains("not found")
                || message.localizedCaseInsensitiveContains("not installed") {
                return "Pi CLI missing"
            }
            return "Pi unavailable"
        }
    }

    var detail: String? {
        if case .unavailable(let message) = self { return message }
        return nil
    }

    var color: Color {
        switch self {
        case .ready, .connected: Theme.positive
        case .connecting: Theme.warning
        case .unavailable: Theme.danger
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSection: AppSection = .overview
    @Published var workspaceScope: PiWorkspaceScope = .workspace
    @Published var connectionState: PiConnectionState = .ready
    @Published var currentProject = ""
    @Published var currentProjectPath = ""
    @Published var composerText = ""
    @Published var isPiRunning = false
    @Published private(set) var messages: [PiChatMessage] = []
    @Published private(set) var activities: [PiActivity] = []
    @Published private(set) var uiRequest: PiUIRequest?
    @Published private(set) var isGenerating = false
    @Published private(set) var agentStatus = "Ready"
    @Published private(set) var sessionName = "New session"
    @Published private(set) var sessionModel = "Model not selected"
    @Published private(set) var sessionId: String?
    @Published private(set) var availableModels: [PiModelOption] = []
    @Published private(set) var thinkingLevel = "off"
    @Published private(set) var savedSessions: [PiSavedSession] = []
    @Published private(set) var projectGroups: [PiProjectGroup] = []
    @Published private(set) var workspace: PiWorkspace
    @Published private(set) var workspaces: [PiWorkspace]
    @Published var sessionProjectFilter: String?

    private var pendingPrompt: String?
    private var pendingNewSession = false
    private var pendingSession: PiSavedSession?
    private var activeTaskId: String?
    private var isRefreshingCatalog = false
    private var needsCatalogRefresh = false

    let piClient = PiRPCClient()
    let usageStore = AccountUsageStore()
    let taskStore = PiTaskStore()
    let piRootDirectory: String
    let globalChatDirectory: String
    let globalKnowledgeDirectory: String

    init() {
        let piRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".pi", isDirectory: true)
        piRootDirectory = piRoot.path
        globalChatDirectory = piRoot.appendingPathComponent("chat", isDirectory: true).path
        globalKnowledgeDirectory = piRoot.appendingPathComponent("knowledge", isDirectory: true).path
        Self.ensureDirectory(at: globalChatDirectory)
        Self.ensureDirectory(at: globalKnowledgeDirectory)

        let registeredPaths = Self.discoverWorkspacePaths()
        if registeredPaths.isEmpty {
            workspaceScope = .global
            workspace = PiWorkspaceInspector.placeholder(path: globalChatDirectory)
            workspaces = []
            currentProject = "Global Chat"
            currentProjectPath = globalChatDirectory
        } else {
            let initialWorkspaces = registeredPaths.map { PiWorkspaceInspector.placeholder(path: $0) }
            workspace = initialWorkspaces[0]
            workspaces = initialWorkspaces
            currentProject = workspace.name
            currentProjectPath = workspace.path
        }

        if PiLaunchConfiguration.resolvedExecutable() == nil {
            connectionState = .unavailable(PiLaunchConfiguration.missingMessage)
        }
    }

    func connectPi() {
        guard !isPiRunning else { return }
        connectionState = .connecting
        piClient.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        piClient.onUIRequest = { [weak self] request in
            Task { @MainActor in
                guard let self else { return }
                self.uiRequest = request
                self.taskStore.update(
                    id: self.activeTaskId,
                    state: .waiting,
                    detail: request.title.isEmpty ? "Waiting for input" : request.title
                )
            }
        }
        piClient.onError = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                self.isGenerating = false
                self.agentStatus = message
                self.taskStore.update(
                    id: self.activeTaskId,
                    state: .finished,
                    detail: message,
                    unread: true
                )
            }
        }
        piClient.onTermination = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                self.isPiRunning = false
                self.isGenerating = false
                self.connectionState = .unavailable(message)
                self.agentStatus = message
                self.taskStore.update(
                    id: self.activeTaskId,
                    state: .finished,
                    detail: message,
                    unread: true
                )
            }
        }
        piClient.start(
            workingDirectory: activeWorkingDirectory,
            projectTrusted: true
        ) { [weak self] success, message in
            Task { @MainActor in
                guard let self else { return }
                self.isPiRunning = success
                self.connectionState = success ? .connected : .unavailable(message)
                if success {
                    self.sessionModel = self.piClient.configuredModelLabel(for: self.activeWorkingDirectory) ?? self.sessionModel
                    self.usageStore.refresh()
                    if self.pendingSession == nil && !self.pendingNewSession {
                        self.reloadSession()
                    }
                    self.loadModels()
                    self.refreshSavedSessions()
                    if let pendingPrompt = self.pendingPrompt {
                        self.pendingPrompt = nil
                        self.send(text: pendingPrompt)
                    }
                    if self.pendingNewSession {
                        self.pendingNewSession = false
                        self.createNewSession()
                    }
                    if let pendingSession = self.pendingSession {
                        self.pendingSession = nil
                        self.switchSession(pendingSession)
                    }
                }
            }
        }
    }

    func sendPrompt() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composerText = ""
        selectedSection = .sessions
        if !isPiRunning {
            pendingPrompt = text
            connectPi()
        } else {
            send(text: text)
        }
    }

    func startNewSession() {
        selectedSection = .sessions
        guard isPiRunning else {
            pendingNewSession = true
            agentStatus = "Connecting to Pi…"
            connectPi()
            return
        }

        createNewSession()
    }

    private func createNewSession() {
        agentStatus = "Creating session…"
        piClient.newSession(
            workingDirectory: activeWorkingDirectory,
            projectTrusted: true
        ) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.activeTaskId = nil
                    self.sessionId = nil
                    self.messages = []
                    self.activities = []
                    self.sessionName = "New session"
                    self.agentStatus = "Ready"
                    self.reloadSession()
                    self.refreshSavedSessions()
                } else {
                    self.agentStatus = "Unable to create session"
                }
            }
        }
    }

    func stopGeneration() {
        piClient.abort { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                self.agentStatus = success ? "Stopped" : "Unable to stop"
                self.isGenerating = false
                self.taskStore.update(
                    id: self.activeTaskId,
                    state: .finished,
                    detail: success ? "Stopped" : "Unable to stop",
                    unread: true
                )
            }
        }
    }

    func respondToUIRequest(value: String? = nil, confirmed: Bool? = nil, cancelled: Bool = false) {
        guard let request = uiRequest else { return }
        uiRequest = nil
        piClient.respondToUIRequest(
            id: request.id,
            value: value,
            confirmed: confirmed,
            cancelled: cancelled
        )
        taskStore.update(id: activeTaskId, state: .running, detail: "Continuing after input")
    }

    func compactSession() {
        guard isPiRunning else { return }
        agentStatus = "Compacting…"
        piClient.compact { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                self.agentStatus = success ? "Compacted" : "Compaction failed"
                self.reloadSession()
            }
        }
    }

    func switchSession(_ session: PiSavedSession) {
        guard isPiRunning else {
            pendingSession = session
            selectedSection = .sessions
            agentStatus = "Connecting to Pi…"
            connectPi()
            return
        }
        agentStatus = "Loading session…"
        piClient.switchSession(path: session.path) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.sessionName = session.title
                    self.sessionId = session.id
                    self.activeTaskId = self.taskStore.taskId(for: session.id)
                    self.messages = []
                    self.activities = []
                    self.reloadSession(loadMessages: true)
                    self.agentStatus = "Ready"
                } else {
                    self.agentStatus = "Unable to load session"
                }
            }
        }
    }

    func selectModel(_ model: PiModelOption) {
        guard isPiRunning else { return }
        agentStatus = "Switching model…"
        piClient.setModel(provider: model.provider, modelId: model.modelId) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.sessionModel = model.identity
                    self.agentStatus = "Ready"
                } else {
                    self.agentStatus = "Unable to switch model"
                }
            }
        }
    }

    func selectThinkingLevel(_ level: String) {
        guard isPiRunning else { return }
        piClient.setThinkingLevel(level) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.thinkingLevel = level
                    self.agentStatus = "Ready"
                } else {
                    self.agentStatus = "Unable to change thinking level"
                }
            }
        }
    }

    private func send(text: String) {
        if let activeTaskId {
            taskStore.resume(id: activeTaskId)
        } else {
            activeTaskId = taskStore.beginOrResume(
                sessionKey: sessionId ?? "pending:\(UUID().uuidString)",
                title: String(text.prefix(100)),
                scopeName: scopeTitle,
                workingDirectory: activeWorkingDirectory
            )
        }
        taskStore.update(id: activeTaskId, state: .running, detail: "Pi is working")
        messages.append(PiChatMessage(id: UUID().uuidString, role: "user", text: text, isStreaming: false))
        activities = []
        isGenerating = true
        agentStatus = "Thinking…"
        piClient.sendPrompt(text)
    }

    private func reloadSession(loadMessages: Bool = true) {
        piClient.requestState { [weak self] state in
            Task { @MainActor in
                guard let self, let state else { return }
                self.sessionId = state.sessionId
                if let sessionId = state.sessionId {
                    self.taskStore.bind(id: self.activeTaskId, to: sessionId)
                    if self.activeTaskId == nil {
                        self.activeTaskId = self.taskStore.taskId(for: sessionId)
                    }
                }
                if let sessionName = state.sessionName {
                    self.sessionName = sessionName
                }
                self.sessionModel = state.model ?? "Model not selected"
                self.thinkingLevel = state.thinkingLevel ?? self.thinkingLevel
                self.agentStatus = state.isStreaming ? "Thinking…" : "Ready"
            }
        }
        if loadMessages {
            piClient.requestMessages { [weak self] messages in
                Task { @MainActor in
                    self?.messages = messages
                }
            }
        }
        piClient.requestSessionStats { [weak self] usage in
            guard let usage else { return }
            Task { @MainActor in
                self?.usageStore.updateSessionUsage(usage)
            }
        }
    }

    private func loadModels() {
        piClient.requestAvailableModels { [weak self] models in
            Task { @MainActor in
                self?.availableModels = models
            }
        }
    }

    func refreshSavedSessions() {
        guard !isRefreshingCatalog else {
            needsCatalogRefresh = true
            return
        }
        isRefreshingCatalog = true
        let workspacePaths = workspaces.map(\.path)
        let sessionRoot = URL(fileURLWithPath: piRootDirectory)
            .appendingPathComponent("agent/sessions", isDirectory: true)
        let globalRoot = globalChatDirectory

        Task {
            let snapshot = await Task.detached(priority: .utility) {
                let sessions = PiSessionCatalog.allSessions(at: sessionRoot)
                let groups = PiSessionCatalog.projectGroups(from: sessions)
                let discoveredPaths = Self.discoveredWorkspacePaths(
                    registeredPaths: workspacePaths,
                    sessions: sessions,
                    excluding: globalRoot
                )
                let inspected = discoveredPaths.map {
                    PiWorkspaceInspector.inspect(path: $0, sessions: sessions)
                }
                return PiCatalogSnapshot(sessions: sessions, groups: groups, workspaces: inspected)
            }.value

            savedSessions = snapshot.sessions
            projectGroups = snapshot.groups
            workspaces = snapshot.workspaces
            taskStore.reconcileSessions(snapshot.sessions)
            if let refreshed = workspaces.first(where: { $0.path == workspace.path }) {
                workspace = refreshed
                if workspaceScope == .workspace {
                    currentProject = refreshed.name
                    currentProjectPath = refreshed.path
                }
            }
            isRefreshingCatalog = false
            if needsCatalogRefresh {
                needsCatalogRefresh = false
                refreshSavedSessions()
            }
        }
    }

    func refreshWorkspace() {
        refreshSavedSessions()
    }

    var activeWorkingDirectory: String {
        workspaceScope == .workspace ? workspace.path : globalChatDirectory
    }

    var scopeTitle: String {
        workspaceScope == .workspace ? workspace.name : "Global Chat"
    }

    var scopePathLabel: String {
        workspaceScope == .workspace ? workspace.path : globalChatDirectory
    }

    var shortenedScopePath: String {
        PiFormat.path(scopePathLabel)
    }

    var isAgentBusy: Bool {
        isGenerating || activities.contains { $0.state == .running }
    }

    var agentStatusCaption: String {
        if let running = activities.last(where: { $0.state == .running }) {
            return "running tool · \(running.toolName)"
        }
        let status = agentStatus.replacingOccurrences(of: "…", with: "").trimmingCharacters(in: .whitespaces)
        switch status {
        case "Ready", "Stopped", "Compacted", "Pi CLI ready":
            return "agent idle"
        case "Thinking":
            return "thinking"
        case "Writing":
            return "writing"
        case "Connecting to Pi":
            return "connecting"
        default:
            return status.lowercased()
        }
    }

    func openTask(_ task: PiTaskRecord) {
        taskStore.markViewed(task)
        guard let key = task.sessionKey, !key.hasPrefix("pending:") else {
            selectedSection = .sessions
            return
        }
        if let session = savedSessions.first(where: { $0.id == key }) {
            sessionProjectFilter = session.cwd
            switchSession(session)
            selectedSection = .sessions
        } else {
            selectedSection = .sessions
        }
    }

    func selectWorkspace(_ selectedWorkspace: PiWorkspace) {
        guard workspaceScope != .workspace || workspace.path != selectedWorkspace.path else { return }
        workspaceScope = .workspace
        workspace = selectedWorkspace
        currentProject = workspace.name
        currentProjectPath = workspace.path
        sessionProjectFilter = nil
        restartPiForScope()
        refreshSavedSessions()
    }

    func selectGlobalScope() {
        guard workspaceScope != .global else { return }
        workspaceScope = .global
        currentProject = "Global Chat"
        sessionProjectFilter = nil
        restartPiForScope()
    }

    func addExistingWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Add Project"
        panel.prompt = "Add Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        registerWorkspace(path: url.path)
    }

    func createWorkspace() {
        let panel = NSSavePanel()
        panel.title = "Create Project"
        panel.prompt = "Create Project"
        panel.nameFieldStringValue = "New Project"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            registerWorkspace(path: url.path)
        } catch {
            agentStatus = "Unable to create project: \(error.localizedDescription)"
        }
    }

    var workspaceSessions: [PiSavedSession] {
        savedSessions.filter { PiWorkspaceInspector.isInside($0.cwd, root: workspace.path) }
    }

    var globalChatSessions: [PiSavedSession] {
        savedSessions.filter { PiWorkspaceInspector.isInside($0.cwd, root: globalChatDirectory) }
    }

    var sidebarSessions: [PiSavedSession] {
        workspaceScope == .global ? globalChatSessions : workspaceSessions
    }

    var workspaceProjectGroups: [PiProjectGroup] {
        projectGroups.filter { PiWorkspaceInspector.isInside($0.cwd, root: workspace.path) }
    }

    var visibleSessions: [PiSavedSession] {
        guard let sessionProjectFilter else {
            return workspaceScope == .global ? globalChatSessions : workspaceSessions
        }
        return savedSessions.filter { $0.cwd == sessionProjectFilter }
    }

    func showProjectSessions(_ project: PiProjectGroup) {
        sessionProjectFilter = project.cwd
        selectedSection = .sessions
    }

    func showAllSessions() {
        sessionProjectFilter = nil
        selectedSection = .sessions
    }

    var projectKnowledgeDirectory: String {
        projectKnowledgeDirectory(for: workspace.path)
    }

    var globalKnowledgeFileCount: Int {
        Self.fileCount(at: globalKnowledgeDirectory)
    }

    var projectKnowledgeFileCount: Int {
        Self.fileCount(at: projectKnowledgeDirectory)
    }

    func openGlobalKnowledge() {
        NSWorkspace.shared.open(URL(fileURLWithPath: globalKnowledgeDirectory))
    }

    func openProjectKnowledge() {
        guard workspaceScope == .workspace else { return }
        Self.ensureDirectory(at: projectKnowledgeDirectory)
        NSWorkspace.shared.open(URL(fileURLWithPath: projectKnowledgeDirectory))
    }

    private func registerWorkspace(path: String) {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: normalizedPath) else { return }
        if !workspaces.contains(where: { $0.path == normalizedPath }) {
            workspaces.append(PiWorkspaceInspector.placeholder(path: normalizedPath))
            UserDefaults.standard.set(workspaces.map(\.path), forKey: "personalPi.workspacePaths")
        }
        if let selected = workspaces.first(where: { $0.path == normalizedPath }) {
            selectWorkspace(selected)
        }
    }

    private func restartPiForScope() {
        if isGenerating {
            taskStore.update(
                id: activeTaskId,
                state: .finished,
                detail: "Interrupted by project switch",
                unread: true
            )
        }
        activeTaskId = nil
        sessionId = nil
        messages = []
        activities = []
        uiRequest = nil
        guard isPiRunning else {
            connectionState = .ready
            return
        }
        piClient.stop()
        isPiRunning = false
        connectionState = .ready
        connectPi()
    }

    private func projectKnowledgeDirectory(for projectPath: String) -> String {
        URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".pi/knowledge", isDirectory: true)
            .path
    }

    private static func discoverWorkspacePaths() -> [String] {
        var paths: [String] = []
        let fileManager = FileManager.default
        func appendIfExists(_ raw: String) {
            let path = URL(fileURLWithPath: raw).standardizedFileURL.path
            guard fileManager.fileExists(atPath: path), !paths.contains(path) else { return }
            paths.append(path)
        }

        for saved in UserDefaults.standard.stringArray(forKey: "personalPi.workspacePaths") ?? [] {
            appendIfExists(saved)
        }

        return paths
    }

    nonisolated private static func discoveredWorkspacePaths(
        registeredPaths: [String],
        sessions: [PiSavedSession],
        excluding globalChatDirectory: String
    ) -> [String] {
        let fileManager = FileManager.default
        var paths: [String] = []

        func appendProject(_ rawPath: String) {
            guard !rawPath.isEmpty else { return }
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  !PiWorkspaceInspector.isInside(path, root: globalChatDirectory),
                  !paths.contains(path) else { return }

            // Explicitly registered roots own nested session directories. A
            // session cwd becomes a project only when no existing project
            // already contains it.
            guard !paths.contains(where: { PiWorkspaceInspector.isInside(path, root: $0) }) else { return }
            paths.append(path)
        }

        registeredPaths.forEach(appendProject)
        sessions.forEach { appendProject($0.cwd) }
        return paths
    }

    private static func ensureDirectory(at path: String) {
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path),
            withIntermediateDirectories: true
        )
    }

    private static func fileCount(at path: String) -> Int {
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return 0 }
        var count = 0
        for case let item as String in enumerator where !item.hasSuffix("/") {
            var isDirectory: ObjCBool = false
            let fullPath = URL(fileURLWithPath: path).appendingPathComponent(item).path
            if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue {
                count += 1
            }
        }
        return count
    }

    private func handle(_ event: PiStreamEvent) {
        switch event.type {
        case "agent_start", "turn_start":
            isGenerating = true
            agentStatus = "Thinking…"
        case "message_update":
            if let delta = event.delta, !delta.isEmpty {
                isGenerating = true
                agentStatus = "Writing…"
                if let index = messages.lastIndex(where: { $0.role == "assistant" && $0.isStreaming }) {
                    messages[index].text += delta
                } else {
                    messages.append(PiChatMessage(id: UUID().uuidString, role: "assistant", text: delta, isStreaming: true))
                }
            }
        case "message_end":
            if event.role == nil || event.role == "assistant", let text = event.messageText, !text.isEmpty {
                if let index = messages.lastIndex(where: { $0.role == "assistant" && $0.isStreaming }) {
                    messages[index].text = text
                    messages[index].isStreaming = false
                } else {
                    messages.append(PiChatMessage(id: UUID().uuidString, role: "assistant", text: text, isStreaming: false))
                }
            }
        case "tool_execution_start":
            let toolName = event.toolName ?? "tool"
            upsertActivity(
                id: event.toolCallId ?? "tool-\(toolName)",
                toolName: toolName,
                detail: event.toolDetail ?? "Running…",
                state: .running
            )
            agentStatus = "Running \(toolName)…"
            taskStore.update(id: activeTaskId, state: .running, detail: "Running \(toolName)")
        case "tool_execution_update":
            let toolName = event.toolName ?? "tool"
            upsertActivity(
                id: event.toolCallId ?? "tool-\(toolName)",
                toolName: toolName,
                detail: event.toolDetail ?? "Running…",
                state: .running
            )
            agentStatus = "Running \(toolName)…"
            taskStore.update(id: activeTaskId, state: .running, detail: "Running \(toolName)")
        case "tool_execution_end":
            let toolName = event.toolName ?? "tool"
            upsertActivity(
                id: event.toolCallId ?? "tool-\(toolName)",
                toolName: toolName,
                detail: event.toolDetail ?? (event.toolIsError == true ? "Tool failed" : "Completed"),
                state: event.toolIsError == true ? .failed : .completed
            )
            agentStatus = event.toolIsError == true ? "Tool failed" : "Processing result…"
        case "compaction_start":
            agentStatus = "Compacting…"
        case "compaction_end":
            agentStatus = "Compacted"
        case "agent_settled", "turn_end":
            isGenerating = false
            agentStatus = "Ready"
            taskStore.update(id: activeTaskId, state: .finished, detail: "Completed", unread: true)
            piClient.requestSessionStats { [weak self] usage in
                guard let usage else { return }
                Task { @MainActor in
                    self?.usageStore.updateSessionUsage(usage)
                }
            }
        case "extension_error":
            isGenerating = false
            agentStatus = "Extension error"
            taskStore.update(id: activeTaskId, state: .finished, detail: "Extension error", unread: true)
        default:
            break
        }
    }

    private func upsertActivity(id: String, toolName: String, detail: String, state: PiActivityState) {
        if let index = activities.firstIndex(where: { $0.id == id }) {
            activities[index].toolName = toolName
            activities[index].detail = detail
            activities[index].state = state
            if state != .running {
                activities[index].endedAt = activities[index].endedAt ?? Date()
            }
        } else {
            activities.append(
                PiActivity(
                    id: id,
                    toolName: toolName,
                    detail: detail,
                    state: state,
                    startedAt: Date(),
                    endedAt: state == .running ? nil : Date()
                )
            )
        }
    }
}

private enum PiSessionCatalog {
    static func allSessions(at root: URL) -> [PiSavedSession] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [] }

        var sessions: [PiSavedSession] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let header = readHeader(from: url) ?? [:]
            guard header["type"] as? String == "session" else { continue }
            let id = header["id"] as? String ?? url.deletingPathExtension().lastPathComponent
            let cwd = header["cwd"] as? String ?? ""
            let timestampText = header["timestamp"] as? String
            let timestamp = timestampText.flatMap { date(from: $0) }
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? Date.distantPast
            sessions.append(PiSavedSession(id: id, path: url.path, timestamp: timestamp, cwd: cwd))
        }
        return sessions.sorted { $0.timestamp > $1.timestamp }
    }

    static func projectGroups(from sessions: [PiSavedSession]) -> [PiProjectGroup] {
        Dictionary(grouping: sessions, by: \.cwd)
            .map { cwd, sessions in
                PiProjectGroup(
                    id: cwd.isEmpty ? "unknown" : cwd,
                    cwd: cwd,
                    sessions: sessions.sorted { $0.timestamp > $1.timestamp }
                )
            }
            .sorted { lhs, rhs in
                (lhs.latestSession?.timestamp ?? .distantPast) > (rhs.latestSession?.timestamp ?? .distantPast)
            }
    }

    private static func readHeader(from url: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 8192)
        guard let firstLine = String(data: data, encoding: .utf8)?.split(separator: "\n", maxSplits: 1).first,
              let lineData = firstLine.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
    }

    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
