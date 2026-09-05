import Foundation
import SwiftUI
import AppKit

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case sessions
    case knowledge
    case packages
    case projects
    case tasks
    case diagnostics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .sessions: "Sessions"
        case .knowledge: "Knowledge"
        case .packages: "Packages"
        case .projects: "Projects"
        case .tasks: "Tasks"
        case .diagnostics: "Diagnostics"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .overview: "diamond"
        case .sessions: "square.on.square"
        case .knowledge: "books.vertical"
        case .packages: "shippingbox"
        case .projects: "tablecells"
        case .tasks: "diamond.inset.filled"
        case .diagnostics: "stethoscope"
        case .settings: "gearshape"
        }
    }
}

struct PiSlashCommand: Identifiable, Sendable, Hashable {
    let name: String
    let description: String
    let source: String
    let location: String?
    let path: String?

    var id: String { "\(source):\(name):\(path ?? "")" }

    var invocation: String { "/\(name)" }

    var sourceLabel: String {
        if source == "native" { return "GUI" }
        if let location, !location.isEmpty {
            return "\(source.capitalized) · \(location.capitalized)"
        }
        return source.capitalized
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

enum PiProviderAccountIntent: String, Sendable {
    case manage
    case login
    case logout
}

struct PiProviderAccountRequest: Identifiable, Sendable {
    let id = UUID()
    let intent: PiProviderAccountIntent
    let providerReference: String?
}

enum PiSessionUtilityKind: String, Sendable {
    case info
    case tree
    case fork
}

struct PiSessionUtilityRequest: Identifiable, Sendable {
    let id = UUID()
    let kind: PiSessionUtilityKind
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
    @Published private(set) var sessionFile: String?
    @Published private(set) var sessionMessageCount = 0
    @Published private(set) var sessionTree: [PiSessionTreeNode] = []
    @Published private(set) var sessionTreeLeafId: String?
    @Published private(set) var forkMessages: [PiForkMessage] = []
    @Published private(set) var isSessionUtilityLoading = false
    @Published private(set) var sessionUtilityError = ""
    @Published var sessionUtilityRequest: PiSessionUtilityRequest?
    @Published private(set) var availableModels: [PiModelOption] = []
    @Published private(set) var availableThinkingLevels = ["off"]
    @Published private(set) var availableCommands: [PiSlashCommand] = AppState.nativeCommands
    @Published private(set) var thinkingLevel = "off"
    @Published private(set) var savedSessions: [PiSavedSession] = []
    @Published private(set) var projectGroups: [PiProjectGroup] = []
    @Published private(set) var workspace: PiWorkspace
    @Published private(set) var workspaces: [PiWorkspace]
    @Published var sessionProjectFilter: String?
    @Published var providerAccountRequest: PiProviderAccountRequest?
    @Published var isArtifactSidebarVisible = false

    private var pendingPrompt: String?
    private var pendingNewSession = false
    private var pendingSession: PiSavedSession?
    private var pendingSessionReference: String?
    private var activeTaskId: String?
    private var isRefreshingCatalog = false
    private var needsCatalogRefresh = false

    let piClient = PiRPCClient()
    let usageStore = AccountUsageStore()
    let taskStore = PiTaskStore()
    let figureArtifactStore: FigureArtifactStore
    let knowledgeStore: KnowledgeLibraryStore
    let piRootDirectory: String
    let globalChatDirectory: String
    let globalKnowledgeDirectory: String

    init() {
        let piRoot = PersonalPiRuntimeEnvironment.piRootURL
        knowledgeStore = KnowledgeLibraryStore(piRoot: piRoot)
        figureArtifactStore = FigureArtifactStore(
            storageURL: piRoot
                .appendingPathComponent("agent", isDirectory: true)
                .appendingPathComponent("personal-pi-figure-artifacts.json")
        )
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
        figureArtifactStore.selectLatest(sessionId: nil, cwd: currentProjectPath)

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
                    self.refreshCommands()
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
        if executeNativeCommand(text) {
            return
        }
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
                    self.sessionFile = nil
                    self.sessionMessageCount = 0
                    self.figureArtifactStore.selectLatest(
                        sessionId: nil,
                        cwd: self.activeWorkingDirectory
                    )
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

    func compactSession(customInstructions: String? = nil) {
        guard isPiRunning else { return }
        agentStatus = "Compacting…"
        piClient.compact(customInstructions: customInstructions) { [weak self] success in
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
                    self.figureArtifactStore.selectLatest(
                        sessionId: session.id,
                        cwd: session.cwd
                    )
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

    func resumeSession(matching reference: String = "") {
        selectedSection = .sessions
        let query = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            refreshSavedSessions()
            agentStatus = "Choose a saved session"
            return
        }
        if let session = matchingSavedSession(query) {
            switchSession(session)
            return
        }
        pendingSessionReference = query
        agentStatus = "Searching saved sessions…"
        refreshSavedSessions()
    }

    func presentSessionInfo() {
        selectedSection = .sessions
        sessionUtilityError = ""
        sessionUtilityRequest = PiSessionUtilityRequest(kind: .info)
        if isPiRunning { reloadSession(loadMessages: false) }
    }

    func presentSessionTree() {
        selectedSection = .sessions
        guard isPiRunning else {
            agentStatus = "Connect to Pi to inspect the session tree"
            return
        }
        sessionTree = []
        sessionTreeLeafId = nil
        sessionUtilityError = ""
        isSessionUtilityLoading = true
        sessionUtilityRequest = PiSessionUtilityRequest(kind: .tree)
        piClient.requestSessionTree { [weak self] tree, leafId in
            Task { @MainActor in
                guard let self else { return }
                self.sessionTree = tree
                self.sessionTreeLeafId = leafId
                self.isSessionUtilityLoading = false
                if tree.isEmpty && self.sessionMessageCount > 0 {
                    self.sessionUtilityError = "Pi returned an empty session tree"
                }
            }
        }
    }

    func presentForkPicker() {
        selectedSection = .sessions
        guard isPiRunning else {
            agentStatus = "Connect to Pi to fork a session"
            return
        }
        forkMessages = []
        sessionUtilityError = ""
        isSessionUtilityLoading = true
        sessionUtilityRequest = PiSessionUtilityRequest(kind: .fork)
        piClient.requestForkMessages { [weak self] messages in
            Task { @MainActor in
                guard let self else { return }
                self.forkMessages = messages
                self.isSessionUtilityLoading = false
                if messages.isEmpty {
                    self.sessionUtilityError = "No user message is available to fork from"
                }
            }
        }
    }

    func navigateSessionTree(to entryId: String, summarize: Bool, customInstructions: String) {
        guard isPiRunning else { return }
        isSessionUtilityLoading = true
        sessionUtilityError = ""
        agentStatus = "Navigating session tree…"
        piClient.navigateTree(
            entryId: entryId,
            summarize: summarize,
            customInstructions: customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyValue
        ) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                self.isSessionUtilityLoading = false
                if success {
                    self.sessionUtilityRequest = nil
                    self.agentStatus = "Session branch selected"
                    self.reloadSession(loadMessages: true)
                } else {
                    self.sessionUtilityError = "Unable to navigate the session tree"
                    self.agentStatus = self.sessionUtilityError
                }
            }
        }
    }

    func forkCurrentSession(from entryId: String) {
        guard isPiRunning else { return }
        isSessionUtilityLoading = true
        sessionUtilityError = ""
        agentStatus = "Forking session…"
        piClient.forkSession(entryId: entryId) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isSessionUtilityLoading = false
                guard let result, !result.cancelled else {
                    self.sessionUtilityError = result?.cancelled == true
                        ? "Session fork was cancelled"
                        : "Unable to fork session"
                    self.agentStatus = self.sessionUtilityError
                    return
                }
                self.sessionUtilityRequest = nil
                self.activeTaskId = nil
                self.messages = []
                self.activities = []
                self.composerText = result.text
                self.agentStatus = result.text.isEmpty ? "Session forked" : "Session forked · original prompt restored"
                self.reloadSession(loadMessages: true)
                self.refreshSavedSessions()
            }
        }
    }

    func cloneCurrentSession() {
        guard isPiRunning else {
            agentStatus = "Connect to Pi to clone a session"
            return
        }
        agentStatus = "Cloning session…"
        piClient.cloneSession { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                guard success else {
                    self.agentStatus = "Unable to clone session"
                    return
                }
                self.activeTaskId = nil
                self.messages = []
                self.activities = []
                self.agentStatus = "Session cloned"
                self.reloadSession(loadMessages: true)
                self.refreshSavedSessions()
            }
        }
    }

    func exportCurrentSession(outputPath: String? = nil) {
        guard isPiRunning else {
            agentStatus = "Connect to Pi to export a session"
            return
        }
        agentStatus = "Exporting session…"
        piClient.exportHTML(outputPath: outputPath?.nonEmptyValue) { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                guard let path else {
                    self.agentStatus = "Unable to export session"
                    return
                }
                self.agentStatus = "Exported session"
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    func copyLastAssistantReply() {
        guard isPiRunning else {
            agentStatus = "Connect to Pi to copy the last reply"
            return
        }
        piClient.requestLastAssistantText { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                guard let text, !text.isEmpty else {
                    self.agentStatus = "No assistant reply to copy"
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.agentStatus = "Last assistant reply copied"
            }
        }
    }

    func reloadPiResources() {
        guard isPiRunning else {
            agentStatus = "Connect to Pi to reload resources"
            return
        }
        agentStatus = "Reloading Pi resources…"
        piClient.reloadResources { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                self.agentStatus = success ? "Pi resources reloaded" : "Unable to reload Pi resources"
                if success {
                    self.reloadSession(loadMessages: true)
                    self.loadModels()
                    self.refreshCommands()
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
                    self.loadAvailableThinkingLevels()
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
                self.figureArtifactStore.selectLatest(
                    sessionId: state.sessionId,
                    cwd: self.activeWorkingDirectory
                )
                self.sessionFile = state.sessionFile
                self.sessionMessageCount = state.messageCount
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
                self.loadAvailableThinkingLevels()
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

    private func loadAvailableThinkingLevels() {
        guard isPiRunning else {
            availableThinkingLevels = ["off"]
            return
        }
        piClient.requestAvailableThinkingLevels { [weak self] levels in
            Task { @MainActor in
                self?.availableThinkingLevels = levels
            }
        }
    }

    func presentProviderAccounts(
        intent: PiProviderAccountIntent = .manage,
        providerReference: String? = nil
    ) {
        let reference = providerReference?.trimmingCharacters(in: .whitespacesAndNewlines)
        providerAccountRequest = PiProviderAccountRequest(
            intent: intent,
            providerReference: reference?.isEmpty == false ? reference : nil
        )
    }

    func refreshCommands() {
        guard isPiRunning else {
            availableCommands = Self.nativeCommands
            return
        }
        piClient.requestCommands { [weak self] commands in
            Task { @MainActor in
                guard let self else { return }
                let nativeNames = Set(Self.nativeCommands.map(\.name))
                self.availableCommands = Self.nativeCommands + commands.filter {
                    !nativeNames.contains($0.name) && !$0.name.hasPrefix("__personal_pi_")
                }
            }
        }
    }

    func applySettingsChange() {
        sessionModel = piClient.configuredModelLabel(for: activeWorkingDirectory) ?? sessionModel
        availableCommands = Self.nativeCommands
        refreshSavedSessions()
        guard isPiRunning else {
            resetIdleConnectionState()
            return
        }
        if let sessionId,
           let currentSession = savedSessions.first(where: { $0.id == sessionId }) {
            pendingSession = currentSession
        }
        agentStatus = "Reloading settings…"
        restartPiForScope()
    }

    func insertSlashCommand(_ command: PiSlashCommand) {
        composerText = command.invocation + " "
    }

    private func executeNativeCommand(_ input: String) -> Bool {
        guard input.hasPrefix("/") else { return false }
        let parts = input.dropFirst().split(maxSplits: 1) { $0.isWhitespace }
        guard let rawName = parts.first else { return false }
        let name = rawName.lowercased()
        let argument = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard Self.nativeCommands.contains(where: { $0.name == name }) else { return false }

        switch name {
        case "settings":
            selectedSection = .settings
            agentStatus = "Ready"
        case "new":
            startNewSession()
        case "compact":
            compactSession(customInstructions: argument.nonEmptyValue)
        case "model":
            guard !argument.isEmpty else {
                selectedSection = .settings
                agentStatus = "Choose a model in Settings"
                return true
            }
            if let model = availableModels.first(where: {
                $0.identity.caseInsensitiveCompare(argument) == .orderedSame
                    || $0.modelId.caseInsensitiveCompare(argument) == .orderedSame
            }) {
                selectModel(model)
            } else {
                agentStatus = "Unknown model: \(argument)"
            }
        case "thinking":
            guard availableThinkingLevels.contains(argument.lowercased()) else {
                selectedSection = .settings
                agentStatus = argument.isEmpty
                    ? "Choose a thinking level in Settings"
                    : "Thinking level unavailable for this model: \(argument)"
                return true
            }
            selectThinkingLevel(argument.lowercased())
        case "name":
            guard !argument.isEmpty else {
                agentStatus = "Usage: /name <session name>"
                return true
            }
            piClient.setSessionName(argument) { [weak self] success in
                Task { @MainActor in
                    guard let self else { return }
                    self.sessionName = success ? argument : self.sessionName
                    self.agentStatus = success ? "Session renamed" : "Unable to rename session"
                    if success { self.refreshSavedSessions() }
                }
            }
        case "login":
            selectedSection = .settings
            presentProviderAccounts(intent: .login, providerReference: argument)
            agentStatus = "Choose a provider to log in"
        case "logout":
            selectedSection = .settings
            presentProviderAccounts(intent: .logout, providerReference: argument)
            agentStatus = "Choose a provider to log out"
        case "resume":
            resumeSession(matching: argument)
        case "session":
            presentSessionInfo()
        case "tree":
            presentSessionTree()
        case "fork":
            if argument.isEmpty { presentForkPicker() }
            else { forkCurrentSession(from: argument) }
        case "clone":
            cloneCurrentSession()
        case "export":
            exportCurrentSession(outputPath: argument.nonEmptyValue)
        case "copy":
            copyLastAssistantReply()
        case "reload":
            reloadPiResources()
        default:
            return false
        }
        return true
    }

    static let thinkingLevels = ["off", "minimal", "low", "medium", "high", "xhigh", "max"]

    static let nativeCommands: [PiSlashCommand] = [
        PiSlashCommand(name: "settings", description: "Open Global and Project Pi settings", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "new", description: "Start a new session", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "compact", description: "Compact context: /compact [custom instructions]", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "model", description: "Switch model: /model provider/model", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "thinking", description: "Set reasoning level: /thinking high", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "name", description: "Rename this session: /name title", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "login", description: "Configure provider authentication", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "logout", description: "Remove stored provider authentication", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "resume", description: "Open saved sessions or resume by ID", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "session", description: "Show current session path, ID and usage", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "tree", description: "Inspect and navigate the current session tree", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "fork", description: "Fork from an earlier user message", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "clone", description: "Clone the active branch into a new session", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "export", description: "Export the session to HTML", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "copy", description: "Copy the last assistant reply", source: "native", location: nil, path: nil),
        PiSlashCommand(name: "reload", description: "Reload Pi extensions, skills, prompts and themes", source: "native", location: nil, path: nil)
    ]

    func refreshSavedSessions() {
        guard !isRefreshingCatalog else {
            needsCatalogRefresh = true
            return
        }
        isRefreshingCatalog = true
        let workspacePaths = workspaces.map(\.path)
        let piRoot = URL(fileURLWithPath: piRootDirectory, isDirectory: true)
        let globalRoot = globalChatDirectory
        let sessionDirectoryOverride = ProcessInfo.processInfo.environment["PI_CODING_AGENT_SESSION_DIR"]

        Task {
            let snapshot = await Task.detached(priority: .utility) {
                let sessionRoots = PiSessionDirectoryResolver.scanRoots(
                    piRoot: piRoot,
                    globalChatDirectory: globalRoot,
                    projectPaths: workspacePaths,
                    environmentSessionDirectory: sessionDirectoryOverride
                )
                let sessions = PiSessionCatalog.allSessions(at: sessionRoots)
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
            if let reference = pendingSessionReference {
                pendingSessionReference = nil
                if let session = matchingSavedSession(reference) {
                    switchSession(session)
                } else {
                    agentStatus = "Session not found: \(reference)"
                }
            }
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

    private func matchingSavedSession(_ query: String) -> PiSavedSession? {
        let exactID = savedSessions.first { $0.id.caseInsensitiveCompare(query) == .orderedSame }
        let normalizedQuery = query.lowercased()
        let IDPrefix = savedSessions.first { $0.id.lowercased().hasPrefix(normalizedQuery) }
        let exactPath = savedSessions.first { $0.path.caseInsensitiveCompare(query) == .orderedSame }
        return exactID ?? IDPrefix ?? exactPath
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
        figureArtifactStore.selectLatest(sessionId: nil, cwd: selectedWorkspace.path)
        restartPiForScope()
        refreshSavedSessions()
    }

    func selectGlobalScope() {
        guard workspaceScope != .global else { return }
        workspaceScope = .global
        currentProject = "Global Chat"
        sessionProjectFilter = nil
        figureArtifactStore.selectLatest(sessionId: nil, cwd: globalChatDirectory)
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

    func configureKnowledge() {
        knowledgeStore.configure(projectRoot: workspaceScope == .workspace
            ? URL(fileURLWithPath: workspace.path, isDirectory: true) : nil)
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
        availableCommands = Self.nativeCommands
        availableThinkingLevels = ["off"]
        guard isPiRunning else {
            resetIdleConnectionState()
            return
        }
        piClient.stop()
        isPiRunning = false
        connectionState = .ready
        connectPi()
    }

    private func resetIdleConnectionState() {
        connectionState = PiLaunchConfiguration.resolvedExecutable() == nil
            ? .unavailable(PiLaunchConfiguration.missingMessage)
            : .ready
    }

    private func projectKnowledgeDirectory(for projectPath: String) -> String {
        URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".pi/knowledge", isDirectory: true)
            .path
    }

    private static func discoverWorkspacePaths() -> [String] {
        if PersonalPiRuntimeEnvironment.isUITesting {
            return ProcessInfo.processInfo.environment["PERSONAL_PI_UI_PROJECT_ROOT"].map { [$0] } ?? []
        }
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
            if ["knowledge_capture", "knowledge_publish", "knowledge_index"].contains(toolName) {
                knowledgeStore.knowledgeChanged()
            }
            upsertActivity(
                id: event.toolCallId ?? "tool-\(toolName)",
                toolName: toolName,
                detail: event.toolDetail ?? (event.toolIsError == true ? "Tool failed" : "Completed"),
                state: event.toolIsError == true ? .failed : .completed
            )
            if let artifact = event.figureArtifact {
                figureArtifactStore.upsert(artifact)
                isArtifactSidebarVisible = true
            }
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

private extension String {
    var nonEmptyValue: String? { isEmpty ? nil : self }
}

enum PiSessionDirectoryResolver {
    static func scanRoots(
        piRoot: URL,
        globalChatDirectory: String,
        projectPaths: [String],
        environmentSessionDirectory: String? = ProcessInfo.processInfo.environment["PI_CODING_AGENT_SESSION_DIR"],
        homeDirectory: String = NSHomeDirectory()
    ) -> [URL] {
        let globalSettings = readSettings(
            at: piRoot.appendingPathComponent("agent/settings.json")
        )
        let defaultRoot = piRoot
            .appendingPathComponent("agent/sessions", isDirectory: true)
            .standardizedFileURL
        var roots = [defaultRoot]

        let workingDirectories = [globalChatDirectory] + projectPaths
        for workingDirectory in workingDirectories {
            let projectSettings = readSettings(
                at: URL(fileURLWithPath: workingDirectory, isDirectory: true)
                    .appendingPathComponent(".pi/settings.json")
            )
            let effectiveSettings = PiSettingsFile.merge(globalSettings, projectSettings)
            let configuredDirectory = environmentSessionDirectory?.nonEmptyValue
                ?? (effectiveSettings["sessionDir"] as? String)?.nonEmptyValue
            guard let configuredDirectory else { continue }
            roots.append(
                resolve(
                    configuredDirectory,
                    relativeTo: workingDirectory,
                    homeDirectory: homeDirectory
                )
            )
        }

        var seen = Set<String>()
        return roots.filter { root in
            seen.insert(canonicalPath(root)).inserted
        }
    }

    static func resolve(
        _ rawPath: String,
        relativeTo workingDirectory: String,
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        let expanded: String
        if rawPath == "~" {
            expanded = homeDirectory
        } else if rawPath.hasPrefix("~/") {
            expanded = (homeDirectory as NSString).appendingPathComponent(String(rawPath.dropFirst(2)))
        } else if rawPath.hasPrefix("file://"), let fileURL = URL(string: rawPath), fileURL.isFileURL {
            return fileURL.standardizedFileURL
        } else {
            expanded = rawPath
        }

        if (expanded as NSString).isAbsolutePath {
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }
        return URL(fileURLWithPath: expanded, isDirectory: true, relativeTo: URL(fileURLWithPath: workingDirectory, isDirectory: true))
            .absoluteURL
            .standardizedFileURL
    }

    private static func readSettings(at url: URL) -> [String: Any] {
        (try? PiSettingsFile.read(url)) ?? [:]
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

enum PiSessionCatalog {
    static func allSessions(at roots: [URL]) -> [PiSavedSession] {
        var sessionsByPath: [String: PiSavedSession] = [:]
        for root in roots {
            for session in allSessions(at: root) {
                let path = URL(fileURLWithPath: session.path)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
                    .path
                sessionsByPath[path] = session
            }
        }
        return sessionsByPath.values.sorted { $0.timestamp > $1.timestamp }
    }

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
