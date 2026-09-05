import Foundation

struct PiStreamEvent: Sendable {
    let type: String
    let role: String?
    let delta: String?
    let messageText: String?
    let toolName: String?
    let toolCallId: String?
    let toolDetail: String?
    let toolIsError: Bool?
    let usage: SessionUsage?
    let figureArtifact: FigureArtifact?
}

struct PiSessionState: Sendable {
    let sessionId: String?
    let sessionFile: String?
    let sessionName: String?
    let model: String?
    let thinkingLevel: String?
    let isStreaming: Bool
    let messageCount: Int
    let isCompacting: Bool
    let pendingMessageCount: Int

    var isIdle: Bool { !isStreaming && !isCompacting && pendingMessageCount == 0 }
}

enum PiSessionChangeResult: Equatable {
    case changed, cancelled, failed

    static func decode(_ response: [String: Any]) -> Self {
        if response["cancelled"] as? Bool == true ||
            (response["data"] as? [String: Any])?["cancelled"] as? Bool == true { return .cancelled }
        return response["success"] as? Bool == true ? .changed : .failed
    }
}

struct PiSessionTreeNode: Identifiable, Sendable, Hashable {
    let id: String
    let parentId: String?
    let type: String
    let timestamp: Date?
    let role: String?
    let text: String
    let label: String?
    let children: [PiSessionTreeNode]

    var isUserMessage: Bool { type == "message" && role == "user" }

    static func decode(_ object: [String: Any]) -> PiSessionTreeNode? {
        guard let entry = object["entry"] as? [String: Any],
              let id = entry["id"] as? String,
              let type = entry["type"] as? String else { return nil }
        let message = entry["message"] as? [String: Any]
        let role = message?["role"] as? String
        let text = message.flatMap { contentText($0["content"]) }
            ?? entry["summary"] as? String
            ?? entry["name"] as? String
            ?? changeDescription(entry, type: type)
        let timestamp = (entry["timestamp"] as? String).flatMap(parseTimestamp)
        let children = (object["children"] as? [[String: Any]] ?? []).compactMap(decode)
        return PiSessionTreeNode(
            id: id,
            parentId: entry["parentId"] as? String,
            type: type,
            timestamp: timestamp,
            role: role,
            text: text,
            label: object["label"] as? String,
            children: children
        )
    }

    private static func contentText(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let blocks = value as? [[String: Any]] else { return nil }
        let text = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined()
        return text.isEmpty ? nil : text
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func changeDescription(_ entry: [String: Any], type: String) -> String {
        switch type {
        case "model_change":
            return [entry["provider"] as? String, entry["modelId"] as? String]
                .compactMap { $0 }
                .joined(separator: "/")
        case "thinking_level_change":
            return entry["thinkingLevel"] as? String ?? ""
        case "custom":
            return entry["customType"] as? String ?? ""
        case "label":
            return entry["label"] as? String ?? ""
        default:
            return ""
        }
    }
}

struct PiForkMessage: Identifiable, Sendable, Hashable {
    let entryId: String
    let text: String

    var id: String { entryId }
}

struct PiForkResult: Sendable, Hashable {
    let text: String
    let cancelled: Bool
}

struct PiModelOption: Identifiable, Sendable, Hashable {
    let provider: String
    let modelId: String
    let name: String
    let reasoning: Bool
    let supportedThinkingLevels: [String]

    var identity: String { "\(provider)/\(modelId)" }
    var displayName: String { name.isEmpty ? identity : name }
    var id: String { identity }

    static func thinkingLevels(
        reasoning: Bool,
        thinkingLevelMap: [String: Any]?
    ) -> [String] {
        guard reasoning else { return ["off"] }
        return ["off", "minimal", "low", "medium", "high", "xhigh", "max"].filter { level in
            let isExplicitlyDisabled = thinkingLevelMap?[level] is NSNull
            if isExplicitlyDisabled { return false }
            if level == "xhigh" || level == "max" {
                return thinkingLevelMap?.keys.contains(level) == true
            }
            return true
        }
    }

    static func decode(_ object: [String: Any]) -> PiModelOption? {
        guard let provider = object["provider"] as? String,
              let id = object["id"] as? String else { return nil }
        let reasoning = object["reasoning"] as? Bool ?? false
        return PiModelOption(
            provider: provider,
            modelId: id,
            name: object["name"] as? String ?? "",
            reasoning: reasoning,
            supportedThinkingLevels: thinkingLevels(
                reasoning: reasoning,
                thinkingLevelMap: object["thinkingLevelMap"] as? [String: Any]
            )
        )
    }
}

@MainActor
final class PiRPCClient: NSObject {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var writer: PiPipeWriter?
    private var outputBuffer = Data()
    private var onStart: ((Bool, String) -> Void)?
    private struct PendingResponse {
        let completion: ([String: Any]) -> Void
        let timeout: Task<Void, Never>
    }
    private var pendingResponses: [String: PendingResponse] = [:]
    private var interactiveRequestIDs = Set<String>()
    private var interactionRevision = UUID()
    private var generation = UUID()
    private var launchStderr = ""
    private let executableOverride: String?
    private let argumentsOverride: [String]?
    private let environmentOverride: [String: String]?
    private let startupTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private let newSessionTimeout: TimeInterval
    var onEvent: ((PiStreamEvent) -> Void)?
    var onError: ((String) -> Void)?
    var onTermination: ((String) -> Void)?
    var onUIRequest: ((PiUIRequest) -> Void)?

    init(executable: String? = nil, arguments: [String]? = nil, environment: [String: String]? = nil,
         startupTimeout: TimeInterval = 5, requestTimeout: TimeInterval = 30,
         newSessionTimeout: TimeInterval = 2) {
        executableOverride = executable
        argumentsOverride = arguments
        environmentOverride = environment
        self.startupTimeout = startupTimeout
        self.requestTimeout = requestTimeout
        self.newSessionTimeout = newSessionTimeout
        super.init()
    }

    var pendingRequestCount: Int { pendingResponses.count }

    var processIdentifier: Int32? {
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    func configuredModelLabel(for workingDirectory: String) -> String? {
        PiLaunchConfiguration.modelLabel(for: workingDirectory)
    }

    func start(workingDirectory: String, projectTrusted: Bool = true, completion: @escaping (Bool, String) -> Void) {
        guard process == nil else {
            completion(onStart == nil, onStart == nil ? "already running" : "Pi is connecting")
            return
        }

        guard let executable = executableOverride ?? PiLaunchConfiguration.resolvedExecutable() else {
            completion(false, PiLaunchConfiguration.missingMessage)
            return
        }

        let cwd = workingDirectory
        if !FileManager.default.fileExists(atPath: cwd) {
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: cwd),
                    withIntermediateDirectories: true
                )
            } catch {
                completion(false, "Working directory does not exist: \(cwd)")
                return
            }
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = argumentsOverride ?? PiLaunchConfiguration.arguments(projectTrusted: projectTrusted)
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = environmentOverride ?? PiLaunchConfiguration.processEnvironment()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        self.process = process
        self.inputPipe = input
        self.writer = PiPipeWriter(handle: input.fileHandleForWriting)
        self.outputPipe = output
        self.errorPipe = error
        generation = UUID()
        let connection = generation
        outputBuffer = Data()
        launchStderr = ""
        onStart = completion

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == connection else { return }
                self.consume(data)
            }
        }

        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == connection else { return }
                self.launchStderr = String((self.launchStderr + text).suffix(16_384))
            }
        }

        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, self.generation == connection else { return }
                let snippet = self.launchStderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let message = snippet.isEmpty ? "Pi exited with status \(process.terminationStatus)" : snippet
                let wasConnected = self.onStart == nil
                self.disconnect(reason: message)
                if wasConnected { self.onTermination?(message) }
            }
        }

        do {
            try process.run()
            request(type: "get_state", timeout: startupTimeout) { [weak self] response in
                guard let self, self.generation == connection else { return }
                if Self.responseSucceeded(response) {
                    let callback = self.onStart
                    self.onStart = nil
                    callback?(true, "connected")
                } else {
                    self.disconnect(reason: response["error"] as? String ?? "Pi RPC did not respond")
                }
            }
        } catch {
            disconnect(reason: error.localizedDescription)
        }
    }

    func sendPrompt(_ message: String, completion: @escaping (Bool, String?) -> Void = { _, _ in }) {
        request(type: "prompt", fields: ["message": message], timeout: 600) { response in
            completion(Self.responseSucceeded(response), response["error"] as? String)
        }
    }

    func newSession(workingDirectory: String, projectTrusted: Bool = true, completion: @escaping (PiSessionChangeResult) -> Void) {
        let connection = generation
        let interaction = interactionRevision
        request(type: "new_session", timeout: newSessionTimeout) { [weak self] response in
            // Pi 0.84.x can leave new_session pending while idle. Only a timeout
            // in this connection may restart it; a cancelled request never can.
            guard let self, self.generation == connection,
                  response["timedOut"] as? Bool == true else {
                completion(PiSessionChangeResult.decode(response))
                return
            }
            guard self.interactionRevision == interaction else {
                completion(.failed) // Never restart after a human-facing hook.
                return
            }
            self.requestState { [weak self] state in
                guard let self, self.generation == connection else { completion(.cancelled); return }
                guard state?.isIdle == true, self.interactiveRequestIDs.isEmpty,
                      self.interactionRevision == interaction else {
                    completion(.failed)
                    return
                }
                self.stop()
                self.start(workingDirectory: workingDirectory, projectTrusted: projectTrusted) { success, _ in
                    completion(success ? .changed : .failed)
                }
            }
        }
    }

    func abort(completion: ((Bool) -> Void)? = nil) {
        request(type: "abort") { response in
            completion?(Self.responseSucceeded(response))
        }
    }

    func compact(customInstructions: String? = nil, completion: ((Bool) -> Void)? = nil) {
        var fields: [String: Any] = [:]
        if let customInstructions, !customInstructions.isEmpty {
            fields["customInstructions"] = customInstructions
        }
        request(type: "compact", fields: fields, timeout: 600) { response in
            completion?(Self.responseSucceeded(response))
        }
    }

    func requestState(completion: @escaping (PiSessionState?) -> Void) {
        request(type: "get_state") { response in
            guard Self.responseSucceeded(response),
                  let data = response["data"] as? [String: Any] else {
                completion(nil)
                return
            }

            let modelObject = data["model"] as? [String: Any]
            let provider = modelObject?["provider"] as? String
            let modelId = modelObject?["id"] as? String
            let model = [provider, modelId].compactMap { $0 }.joined(separator: "/")

            completion(PiSessionState(
                sessionId: data["sessionId"] as? String,
                sessionFile: data["sessionFile"] as? String,
                sessionName: data["sessionName"] as? String,
                model: model.isEmpty ? nil : model,
                thinkingLevel: data["thinkingLevel"] as? String,
                isStreaming: (data["isStreaming"] as? Bool) ?? false,
                messageCount: (data["messageCount"] as? NSNumber)?.intValue ?? 0,
                isCompacting: data["isCompacting"] as? Bool ?? false,
                pendingMessageCount: (data["pendingMessageCount"] as? NSNumber)?.intValue ?? 0
            ))
        }
    }

    func requestMessages(completion: @escaping ([PiChatMessage]) -> Void) {
        request(type: "get_messages") { response in
            guard Self.responseSucceeded(response),
                  let data = response["data"] as? [String: Any],
                  let rawMessages = data["messages"] as? [[String: Any]] else {
                completion([])
                return
            }
            completion(rawMessages.compactMap(Self.parseChatMessage))
        }
    }

    func switchSession(path: String, completion: @escaping (PiSessionChangeResult) -> Void) {
        request(type: "switch_session", fields: ["sessionPath": path]) { response in
            completion(PiSessionChangeResult.decode(response))
        }
    }

    func requestSessionTree(completion: @escaping ([PiSessionTreeNode], String?) -> Void) {
        request(type: "get_tree") { response in
            guard Self.responseSucceeded(response),
                  let data = response["data"] as? [String: Any] else {
                completion([], nil)
                return
            }
            let tree = (data["tree"] as? [[String: Any]] ?? []).compactMap(PiSessionTreeNode.decode)
            completion(tree, data["leafId"] as? String)
        }
    }

    func requestForkMessages(completion: @escaping ([PiForkMessage]) -> Void) {
        request(type: "get_fork_messages") { response in
            guard Self.responseSucceeded(response),
                  let data = response["data"] as? [String: Any],
                  let messages = data["messages"] as? [[String: Any]] else {
                completion([])
                return
            }
            completion(messages.compactMap { message in
                guard let entryId = message["entryId"] as? String,
                      let text = message["text"] as? String else { return nil }
                return PiForkMessage(entryId: entryId, text: text)
            })
        }
    }

    func forkSession(entryId: String, completion: @escaping (PiForkResult?) -> Void) {
        request(type: "fork", fields: ["entryId": entryId]) { response in
            guard Self.responseSucceeded(response),
                  let data = response["data"] as? [String: Any] else {
                completion(nil)
                return
            }
            completion(PiForkResult(
                text: data["text"] as? String ?? "",
                cancelled: data["cancelled"] as? Bool ?? false
            ))
        }
    }

    func cloneSession(completion: @escaping (Bool) -> Void) {
        request(type: "clone") { response in
            guard Self.responseSucceeded(response),
                  let data = response["data"] as? [String: Any] else {
                completion(false)
                return
            }
            completion((data["cancelled"] as? Bool ?? false) == false)
        }
    }

    func exportHTML(outputPath: String? = nil, completion: @escaping (String?) -> Void) {
        var fields: [String: Any] = [:]
        if let outputPath, !outputPath.isEmpty {
            fields["outputPath"] = outputPath
        }
        request(type: "export_html", fields: fields) { response in
            guard Self.responseSucceeded(response),
                  let data = response["data"] as? [String: Any] else {
                completion(nil)
                return
            }
            completion(data["path"] as? String)
        }
    }

    func requestLastAssistantText(completion: @escaping (String?) -> Void) {
        request(type: "get_last_assistant_text") { response in
            guard Self.responseSucceeded(response),
                  let data = response["data"] as? [String: Any] else {
                completion(nil)
                return
            }
            completion(data["text"] as? String)
        }
    }

    func navigateTree(
        entryId: String,
        summarize: Bool,
        customInstructions: String?,
        completion: @escaping (Bool) -> Void
    ) {
        guard PiLaunchConfiguration.runtimeExtensionURL != nil else {
            completion(false)
            return
        }
        var payload: [String: Any] = ["entryId": entryId, "summarize": summarize]
        if let customInstructions, !customInstructions.isEmpty {
            payload["customInstructions"] = customInstructions
        }
        executeInternalCommand(name: "__personal_pi_navigate", payload: payload, completion: completion)
    }

    func reloadResources(completion: @escaping (Bool) -> Void) {
        guard PiLaunchConfiguration.runtimeExtensionURL != nil else {
            completion(false)
            return
        }
        executeInternalCommand(name: "__personal_pi_reload", payload: [:], completion: completion)
    }

    private func executeInternalCommand(
        name: String,
        payload: [String: Any],
        completion: @escaping (Bool) -> Void
    ) {
        let responseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("personal-pi-runtime-\(UUID().uuidString).json")
        var commandPayload = payload
        commandPayload["responsePath"] = responseURL.path
        guard let data = try? JSONSerialization.data(withJSONObject: commandPayload) else {
            completion(false)
            return
        }
        let message = "/\(name) \(data.base64EncodedString())"
        request(type: "prompt", fields: ["message": message], timeout: 600) { response in
            defer { try? FileManager.default.removeItem(at: responseURL) }
            guard Self.responseSucceeded(response),
                  let data = try? Data(contentsOf: responseURL),
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(false)
                return
            }
            completion(result["success"] as? Bool == true)
        }
    }

    func requestAvailableModels(completion: @escaping ([PiModelOption]) -> Void) {
        request(type: "get_available_models") { response in
            guard Self.responseSucceeded(response),
                  let data = response["data"] as? [String: Any],
                  let models = data["models"] as? [[String: Any]] else {
                completion([])
                return
            }
            completion(models.compactMap(PiModelOption.decode))
        }
    }

    func requestAvailableThinkingLevels(completion: @escaping ([String]) -> Void) {
        request(type: "get_available_thinking_levels") { response in
            guard Self.responseSucceeded(response),
                  let data = response["data"] as? [String: Any],
                  let levels = data["levels"] as? [String],
                  !levels.isEmpty else {
                completion(["off"])
                return
            }
            completion(levels)
        }
    }

    func requestCommands(completion: @escaping ([PiSlashCommand]) -> Void) {
        request(type: "get_commands") { response in
            guard Self.responseSucceeded(response),
                  let data = response["data"] as? [String: Any],
                  let rawCommands = data["commands"] as? [[String: Any]] else {
                completion([])
                return
            }
            completion(rawCommands.compactMap { command in
                guard let name = command["name"] as? String,
                      let source = command["source"] as? String else { return nil }
                return PiSlashCommand(
                    name: name,
                    description: command["description"] as? String ?? "",
                    source: source,
                    location: command["location"] as? String,
                    path: command["path"] as? String
                )
            })
        }
    }

    func setModel(provider: String, modelId: String, completion: ((Bool) -> Void)? = nil) {
        request(type: "set_model", fields: ["provider": provider, "modelId": modelId]) { response in
            completion?(Self.responseSucceeded(response))
        }
    }

    func setThinkingLevel(_ level: String, completion: ((Bool) -> Void)? = nil) {
        request(type: "set_thinking_level", fields: ["level": level]) { response in
            completion?(Self.responseSucceeded(response))
        }
    }

    func setSessionName(_ name: String, completion: ((Bool) -> Void)? = nil) {
        request(type: "set_session_name", fields: ["name": name]) { response in
            completion?(Self.responseSucceeded(response))
        }
    }

    func respondToUIRequest(id: String, value: String? = nil, confirmed: Bool? = nil, cancelled: Bool = false) {
        interactiveRequestIDs.remove(id)
        interactionRevision = UUID()
        var command: [String: Any] = [
            "type": "extension_ui_response",
            "id": id
        ]
        if cancelled {
            command["cancelled"] = true
        } else if let confirmed {
            command["confirmed"] = confirmed
        } else if let value {
            command["value"] = value
        }
        send(command: command)
    }

    func requestSessionStats(completion: @escaping (SessionUsage?) -> Void) {
        request(type: "get_session_stats") { response in
            guard let data = response["data"] as? [String: Any],
                  let tokens = data["tokens"] as? [String: Any] else {
                completion(nil)
                return
            }

            let contextUsage = data["contextUsage"] as? [String: Any]
            let contextPercent = contextUsage?["percent"] as? Double
                ?? (contextUsage?["percent"] as? NSNumber)?.doubleValue

            completion(SessionUsage(
                inputTokens: (tokens["input"] as? NSNumber)?.intValue ?? 0,
                outputTokens: (tokens["output"] as? NSNumber)?.intValue ?? 0,
                totalTokens: (tokens["total"] as? NSNumber)?.intValue ?? 0,
                cost: (data["cost"] as? NSNumber)?.doubleValue ?? 0,
                contextPercent: contextPercent
            ))
        }
    }

    func stop() {
        disconnect(reason: "Pi connection closed")
    }

    private func disconnect(reason: String) {
        interactiveRequestIDs.removeAll()
        generation = UUID()
        let oldProcess = process
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        oldProcess?.terminationHandler = nil
        writer?.close()
        writer = nil
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        outputBuffer = Data()
        let startup = onStart
        onStart = nil
        let pending = pendingResponses
        pendingResponses.removeAll()
        for response in pending.values { response.timeout.cancel() }
        if let oldProcess, oldProcess.isRunning {
            oldProcess.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if oldProcess.isRunning { kill(oldProcess.processIdentifier, SIGKILL) }
            }
        }
        startup?(false, reason)
        for response in pending.values {
            response.completion(["success": false, "error": reason, "cancelled": true])
        }
    }

    private func request(type: String, fields: [String: Any] = [:], timeout: TimeInterval? = nil,
                         completion: @escaping ([String: Any]) -> Void) {
        guard inputPipe != nil else {
            completion(["success": false, "error": "Pi is not connected"])
            return
        }
        let id = UUID().uuidString
        let connection = generation
        let interaction = interactionRevision
        let duration = timeout ?? requestTimeout
        let timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            // After a dialog closes, Pi still needs time to acknowledge its
            // result. Closing the UI is not completion of the session operation.
            var lastInteraction = interaction
            while type == "new_session", let self, self.generation == connection,
                  self.pendingResponses[id] != nil {
                if !self.interactiveRequestIDs.isEmpty {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                } else if self.interactionRevision != lastInteraction {
                    lastInteraction = self.interactionRevision
                    do { try await Task.sleep(for: .seconds(self.requestTimeout)) } catch { return }
                } else {
                    break
                }
            }
            guard let self, self.generation == connection,
                  let response = self.pendingResponses.removeValue(forKey: id) else { return }
            response.completion(["success": false, "error": "Pi \(type) timed out", "timedOut": true])
        }
        pendingResponses[id] = PendingResponse(completion: completion, timeout: timer)
        var command = fields
        command["id"] = id
        command["type"] = type
        send(command: command)
    }

    private func send(command: [String: Any]) {
        guard let writer, let data = try? JSONSerialization.data(withJSONObject: command) else { return }
        let connection = generation
        writer.write(data + Data([0x0A])) { [weak self] message in
            DispatchQueue.main.async {
                guard let self, self.generation == connection else { return }
                self.disconnect(reason: message)
                self.onTermination?(message)
            }
        }
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if object["type"] as? String == "response" {
                if let id = object["id"] as? String,
                   let response = pendingResponses.removeValue(forKey: id) {
                    response.timeout.cancel()
                    response.completion(object)
                }
                if object["success"] as? Bool == false {
                    onError?(object["error"] as? String ?? "Pi RPC command failed")
                }
            } else if object["type"] as? String == "extension_ui_request",
                      let request = Self.parseUIRequest(object) {
                if ["select", "confirm", "input", "editor"].contains(request.method) {
                    interactiveRequestIDs.insert(request.id)
                    interactionRevision = UUID()
                }
                onUIRequest?(request)
            } else if let event = Self.parseEvent(object) {
                onEvent?(event)
            }
        }
    }

    nonisolated private static func responseSucceeded(_ response: [String: Any]) -> Bool {
        (response["success"] as? Bool) == true
    }

    nonisolated static func parseEvent(_ object: [String: Any]) -> PiStreamEvent? {
        guard let type = object["type"] as? String else { return nil }

        var delta: String?
        var messageText: String?
        var toolName: String?
        var toolCallId: String?
        var toolDetail: String?
        var toolIsError: Bool?
        var role: String?
        var figureArtifact: FigureArtifact?

        if let assistantEvent = object["assistantMessageEvent"] as? [String: Any] {
            let assistantEventType = assistantEvent["type"] as? String
            if assistantEventType == "text_delta" {
                delta = assistantEvent["delta"] as? String
            }
            if assistantEventType == "toolcall_start" || assistantEventType == "toolcall_end" {
                toolCallId = assistantEvent["id"] as? String
                toolName = assistantEvent["toolName"] as? String
                if assistantEventType == "toolcall_end" {
                    toolDetail = jsonString(assistantEvent["toolCall"])
                }
            }
        }

        if type == "message_end",
           let message = object["message"] as? [String: Any] {
            role = message["role"] as? String
            messageText = parseContent(message["content"])
        }

        if type == "tool_execution_start" {
            toolCallId = object["toolCallId"] as? String
            toolName = object["toolName"] as? String
            toolDetail = jsonString(object["args"])
        }

        if type == "tool_execution_update" {
            toolCallId = object["toolCallId"] as? String
            toolName = object["toolName"] as? String
            if let partialResult = object["partialResult"] as? [String: Any] {
                toolDetail = parseContent(partialResult["content"])
            }
        }

        if type == "tool_execution_end" {
            toolCallId = object["toolCallId"] as? String
            toolName = object["toolName"] as? String
            toolIsError = object["isError"] as? Bool
            if let result = object["result"] as? [String: Any] {
                toolDetail = parseContent(result["content"])
                if let details = result["details"] as? [String: Any] {
                    figureArtifact = FigureArtifact.decode(details["personalPiFigureArtifact"])
                }
            }
        }

        return PiStreamEvent(
            type: type,
            role: role,
            delta: delta,
            messageText: messageText,
            toolName: toolName,
            toolCallId: toolCallId,
            toolDetail: toolDetail,
            toolIsError: toolIsError,
            usage: parseUsage(object["usage"]),
            figureArtifact: figureArtifact
        )
    }

    nonisolated private static func parseUIRequest(_ object: [String: Any]) -> PiUIRequest? {
        guard let id = object["id"] as? String,
              let method = object["method"] as? String else { return nil }
        return PiUIRequest(
            id: id,
            method: method,
            title: object["title"] as? String ?? "Pi needs your input",
            message: object["message"] as? String ?? "",
            options: object["options"] as? [String] ?? [],
            placeholder: object["placeholder"] as? String ?? "",
            prefill: object["prefill"] as? String ?? ""
        )
    }

    nonisolated private static func parseChatMessage(_ object: [String: Any]) -> PiChatMessage? {
        let message = object["message"] as? [String: Any] ?? object
        guard let role = message["role"] as? String else { return nil }
        let text = parseContent(message["content"]) ?? ""
        guard !text.isEmpty else { return nil }
        return PiChatMessage(id: object["id"] as? String ?? UUID().uuidString, role: role, text: text, isStreaming: false)
    }

    nonisolated private static func parseContent(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let blocks = value as? [[String: Any]] {
            let text = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    nonisolated private static func parseUsage(_ value: Any?) -> SessionUsage? {
        guard let usage = value as? [String: Any] else { return nil }
        let costObject = usage["cost"] as? [String: Any]
        return SessionUsage(
            inputTokens: (usage["input"] as? NSNumber)?.intValue ?? 0,
            outputTokens: (usage["output"] as? NSNumber)?.intValue ?? 0,
            totalTokens: (usage["totalTokens"] as? NSNumber)?.intValue ?? 0,
            cost: (costObject?["total"] as? NSNumber)?.doubleValue ?? 0,
            contextPercent: nil
        )
    }

    nonisolated private static func jsonString(_ value: Any?) -> String? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}

enum PiLaunchConfiguration {
    static let missingMessage = "Pi CLI not found. Install with: npm install -g --ignore-scripts @earendil-works/pi-coding-agent"

    static func arguments(projectTrusted: Bool) -> [String] {
        // The cwd is supplied to Process by PiRPCClient. Keep provider/model
        // selection in Pi settings so project overrides remain effective.
        var arguments = ["--mode", "rpc", projectTrusted ? "--approve" : "--no-approve"]
        if let runtimeExtensionURL {
            arguments.append(contentsOf: ["--extension", runtimeExtensionURL.path])
        }
        for plugin in bundledPlugins {
            arguments.append(contentsOf: ["--extension", plugin.rootURL.path])
        }
        return arguments
    }

    static var runtimeExtensionURL: URL? {
        let bundled = Bundle.main.url(forResource: "personal-pi-runtime-extension", withExtension: "js")
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/personal-pi-runtime-extension.js")
        return bundled ?? (FileManager.default.fileExists(atPath: development.path) ? development : nil)
    }

    static var bundledPlugins: [BundledPiPlugin] {
        PersonalPiPluginRegistry.discover()
    }

    static var figurePlugin: BundledPiPlugin? {
        bundledPlugins.first { $0.id == "figure" }
    }

    static var figurePluginPackageURL: URL? {
        figurePlugin?.rootURL
    }

    static var knowledgePlugin: BundledPiPlugin? {
        bundledPlugins.first { $0.id == "knowledge" }
    }

    static var knowledgePluginPackageURL: URL? {
        knowledgePlugin?.rootURL
    }

    static func resolvedExecutable() -> String? {
        guard !PersonalPiRuntimeEnvironment.externalProcessesDisabled else { return nil }
        return resolvedExecutable(named: "pi", overrideEnvironmentKey: "PERSONAL_PI_EXECUTABLE")
    }

    static func resolvedNodeExecutable() -> String? {
        guard !PersonalPiRuntimeEnvironment.externalProcessesDisabled else { return nil }
        return resolvedExecutable(named: "node", overrideEnvironmentKey: "PERSONAL_PI_NODE_EXECUTABLE")
    }

    static func resolvedCodexExecutable() -> String? {
        guard !PersonalPiRuntimeEnvironment.externalProcessesDisabled else { return nil }
        return resolvedExecutable(named: "codex", overrideEnvironmentKey: "PERSONAL_PI_CODEX_EXECUTABLE")
    }

    static func resolvedUvExecutable() -> String? {
        guard !PersonalPiRuntimeEnvironment.externalProcessesDisabled else { return nil }
        return resolvedExecutable(named: "uv", overrideEnvironmentKey: "PERSONAL_PI_UV_EXECUTABLE")
    }

    private static func resolvedExecutable(named name: String, overrideEnvironmentKey: String) -> String? {
        var seen = Set<String>()
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment[overrideEnvironmentKey],
           !override.isEmpty {
            candidates.append(override)
        }
        for directory in augmentedPathDirectories() {
            candidates.append((directory as NSString).appendingPathComponent(name))
        }
        for candidate in candidates {
            let path = URL(fileURLWithPath: candidate).standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func processEnvironment() -> [String: String] {
        var environment = PiRuntimeContext.current.processEnvironment(ProcessInfo.processInfo.environment)
        environment["PATH"] = augmentedPathDirectories().joined(separator: ":")
        return environment
    }

    private static func augmentedPathDirectories() -> [String] {
        let home = NSHomeDirectory()
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var directories = inherited.split(separator: ":").map(String.init)
        directories.append(contentsOf: [
            NSHomeDirectory() + "/.local/bin",
            home + "/.npm-global/bin",
            home + "/.volta/bin",
            home + "/.asdf/shims",
            home + "/.local/share/pnpm",
            home + "/Library/pnpm",
            home + "/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ])
        directories.append(contentsOf: nvmBinDirectories())
        directories.append(contentsOf: fnmBinDirectories())
        var seen = Set<String>()
        return directories.filter { seen.insert($0).inserted }
    }

    private static func nvmBinDirectories() -> [String] {
        let versionsRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".nvm/versions/node", isDirectory: true)
        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: versionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return versions
            .filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appendingPathComponent("bin", isDirectory: true).path }
    }

    private static func fnmBinDirectories() -> [String] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let roots = [
            home.appendingPathComponent(".local/share/fnm/node-versions", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/fnm/node-versions", isDirectory: true)
        ]
        var directories: [String] = []
        for root in roots {
            guard let versions = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            directories.append(contentsOf: versions.map {
                $0.appendingPathComponent("installation/bin", isDirectory: true).path
            })
        }
        return directories.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
    }

    static func modelLabel(for workingDirectory: String) -> String? {
        let global = readSettings(at: PiRuntimeContext.current.settingsURL)
        let project = readSettings(at: URL(fileURLWithPath: workingDirectory).appendingPathComponent(".pi/settings.json"))
        let provider = project["defaultProvider"] as? String ?? global["defaultProvider"] as? String
        let model = project["defaultModel"] as? String ?? global["defaultModel"] as? String
        return [provider, model].compactMap { $0 }.joined(separator: "/").nilIfEmpty
    }

    private static func readSettings(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
