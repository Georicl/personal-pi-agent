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
}

struct PiSessionState: Sendable {
    let sessionId: String?
    let sessionFile: String?
    let sessionName: String?
    let model: String?
    let thinkingLevel: String?
    let isStreaming: Bool
    let messageCount: Int
}

struct PiModelOption: Identifiable, Sendable, Hashable {
    let provider: String
    let modelId: String
    let name: String

    var identity: String { "\(provider)/\(modelId)" }
    var displayName: String { name.isEmpty ? identity : name }
    var id: String { identity }
}

final class PiRPCClient: NSObject, @unchecked Sendable {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var outputBuffer = Data()
    private var onStart: (@Sendable (Bool, String) -> Void)?
    private var pendingResponses: [String: ([String: Any]) -> Void] = [:]
    private let stderrLock = NSLock()
    private var launchStderr = ""
    private var didFinishLaunch = false
    var onEvent: ((PiStreamEvent) -> Void)?
    var onError: ((String) -> Void)?
    var onTermination: ((String) -> Void)?
    var onUIRequest: ((PiUIRequest) -> Void)?

    var processIdentifier: Int32? {
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    func configuredModelLabel(for workingDirectory: String) -> String? {
        PiLaunchConfiguration.modelLabel(for: workingDirectory)
    }

    func start(workingDirectory: String, projectTrusted: Bool = true, completion: @escaping @Sendable (Bool, String) -> Void) {
        guard process == nil else {
            completion(true, "already running")
            return
        }

        guard let executable = PiLaunchConfiguration.resolvedExecutable() else {
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
        process.arguments = PiLaunchConfiguration.arguments(projectTrusted: projectTrusted)
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = PiLaunchConfiguration.processEnvironment()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        self.process = process
        self.inputPipe = input
        self.outputPipe = output

        stderrLock.lock()
        launchStderr = ""
        didFinishLaunch = false
        stderrLock.unlock()

        let complete: @Sendable (Bool, String) -> Void = { [weak self] success, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.stderrLock.lock()
                let alreadyFinished = self.didFinishLaunch
                if !alreadyFinished {
                    self.didFinishLaunch = true
                }
                self.stderrLock.unlock()
                guard !alreadyFinished else { return }
                self.onStart = nil
                if !success {
                    self.process = nil
                    self.inputPipe = nil
                    self.outputPipe = nil
                }
                completion(success, message)
            }
        }
        self.onStart = complete

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }

        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            self?.stderrLock.lock()
            self?.launchStderr += text
            self?.stderrLock.unlock()
        }

        process.terminationHandler = { [weak self] process in
            guard let self, self.process === process else { return }
            self.process = nil
            self.inputPipe = nil
            self.outputPipe = nil
            self.stderrLock.lock()
            let snippet = self.launchStderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let launchCompleted = self.didFinishLaunch
            self.stderrLock.unlock()
            let message = snippet.isEmpty ? "Pi exited with status \(process.terminationStatus)" : snippet
            if launchCompleted {
                self.onTermination?(message)
            } else {
                complete(false, message)
            }
        }

        do {
            try process.run()
            request(type: "get_state") { response in
                if Self.responseSucceeded(response) {
                    complete(true, "connected")
                } else {
                    complete(false, response["error"] as? String ?? "Pi RPC did not respond")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.stderrLock.lock()
                let snippet = self?.launchStderr.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self?.stderrLock.unlock()
                complete(false, snippet.isEmpty ? "Pi did not respond" : snippet)
            }
        } catch {
            self.process = nil
            complete(false, error.localizedDescription)
        }
    }

    func sendPrompt(_ message: String) {
        send(command: ["id": UUID().uuidString, "type": "prompt", "message": message])
    }

    func newSession(workingDirectory: String, projectTrusted: Bool = true, completion: @escaping @Sendable (Bool) -> Void) {
        let id = UUID().uuidString
        pendingResponses[id] = { response in
            completion(Self.responseSucceeded(response))
        }
        send(command: ["id": id, "type": "new_session"])

        // Pi 0.84.x can leave new_session pending when there is no active
        // turn. Restarting the RPC process creates the same fresh session
        // while keeping the GUI responsive and preserving Pi's session files.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self,
                  self.pendingResponses.removeValue(forKey: id) != nil else { return }
            self.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.start(workingDirectory: workingDirectory, projectTrusted: projectTrusted) { success, _ in
                    completion(success)
                }
            }
        }
    }

    func abort(completion: ((Bool) -> Void)? = nil) {
        request(type: "abort") { response in
            completion?(Self.responseSucceeded(response))
        }
    }

    func compact(completion: ((Bool) -> Void)? = nil) {
        request(type: "compact") { response in
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
                messageCount: (data["messageCount"] as? NSNumber)?.intValue ?? 0
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

    func switchSession(path: String, completion: @escaping (Bool) -> Void) {
        request(type: "switch_session", fields: ["sessionPath": path]) { response in
            completion(Self.responseSucceeded(response))
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
            completion(models.compactMap { model in
                guard let provider = model["provider"] as? String,
                      let id = model["id"] as? String else { return nil }
                return PiModelOption(
                    provider: provider,
                    modelId: id,
                    name: model["name"] as? String ?? ""
                )
            })
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
        let id = UUID().uuidString
        pendingResponses[id] = { response in
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
        send(command: ["id": id, "type": "get_session_stats"])
    }

    func stop() {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
    }

    private func request(type: String, fields: [String: Any] = [:], completion: @escaping ([String: Any]) -> Void) {
        let id = UUID().uuidString
        pendingResponses[id] = completion
        var command = fields
        command["id"] = id
        command["type"] = type
        send(command: command)
    }

    private func send(command: [String: Any]) {
        guard let inputPipe, let data = try? JSONSerialization.data(withJSONObject: command) else { return }
        inputPipe.fileHandleForWriting.write(data)
        inputPipe.fileHandleForWriting.write(Data([0x0A]))
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if object["type"] as? String == "response" {
                if let id = object["id"] as? String,
                   let callback = pendingResponses.removeValue(forKey: id) {
                    callback(object)
                }
                if object["success"] as? Bool == false {
                    onError?(object["error"] as? String ?? "Pi RPC command failed")
                }
            } else if object["type"] as? String == "extension_ui_request",
                      let request = Self.parseUIRequest(object) {
                onUIRequest?(request)
            } else if let event = Self.parseEvent(object) {
                onEvent?(event)
            }
        }
    }

    private static func responseSucceeded(_ response: [String: Any]) -> Bool {
        (response["success"] as? Bool) == true
    }

    private static func parseEvent(_ object: [String: Any]) -> PiStreamEvent? {
        guard let type = object["type"] as? String else { return nil }

        var delta: String?
        var messageText: String?
        var toolName: String?
        var toolCallId: String?
        var toolDetail: String?
        var toolIsError: Bool?
        var role: String?

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
            usage: parseUsage(object["usage"])
        )
    }

    private static func parseUIRequest(_ object: [String: Any]) -> PiUIRequest? {
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

    private static func parseChatMessage(_ object: [String: Any]) -> PiChatMessage? {
        let message = object["message"] as? [String: Any] ?? object
        guard let role = message["role"] as? String else { return nil }
        let text = parseContent(message["content"]) ?? ""
        guard !text.isEmpty else { return nil }
        return PiChatMessage(id: object["id"] as? String ?? UUID().uuidString, role: role, text: text, isStreaming: false)
    }

    private static func parseContent(_ value: Any?) -> String? {
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

    private static func parseUsage(_ value: Any?) -> SessionUsage? {
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

    private static func jsonString(_ value: Any?) -> String? {
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
        ["--mode", "rpc", projectTrusted ? "--approve" : "--no-approve"]
    }

    static func resolvedExecutable() -> String? {
        resolvedExecutable(named: "pi", overrideEnvironmentKey: "PERSONAL_PI_EXECUTABLE")
    }

    static func resolvedNodeExecutable() -> String? {
        resolvedExecutable(named: "node", overrideEnvironmentKey: "PERSONAL_PI_NODE_EXECUTABLE")
    }

    static func resolvedCodexExecutable() -> String? {
        resolvedExecutable(named: "codex", overrideEnvironmentKey: "PERSONAL_PI_CODEX_EXECUTABLE")
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
        var environment = ProcessInfo.processInfo.environment
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
        let global = readSettings(at: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".pi/agent/settings.json"))
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
