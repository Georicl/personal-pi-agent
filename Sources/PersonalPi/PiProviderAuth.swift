import Foundation

enum PiProviderAuthType: String, Codable, Hashable, Identifiable, Sendable {
    case oauth
    case apiKey = "api_key"

    var id: String { rawValue }
}

struct PiProviderLoginMethod: Codable, Hashable, Identifiable, Sendable {
    let type: PiProviderAuthType
    let name: String
    let loginLabel: String?
    let interactive: Bool
    let subscription: Bool

    var id: PiProviderAuthType { type }
}

struct PiLoginProvider: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let configured: Bool
    let configuredAuthType: PiProviderAuthType?
    let storedAuthType: PiProviderAuthType?
    let methods: [PiProviderLoginMethod]

    var preferredMethod: PiProviderLoginMethod? {
        methods.first(where: { $0.type == .oauth }) ?? methods.first
    }
}

struct PiProviderAuthPromptOption: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let label: String
    let description: String?
}

struct PiProviderAuthPrompt: Codable, Hashable, Sendable {
    let type: String
    let message: String
    let placeholder: String?
    let options: [PiProviderAuthPromptOption]?
}

struct PiProviderAuthLink: Codable, Hashable, Sendable {
    let url: String
    let label: String?
}

struct PiProviderAuthNotification: Codable, Hashable, Sendable {
    let type: String
    let message: String?
    let links: [PiProviderAuthLink]?
    let url: String?
    let instructions: String?
    let userCode: String?
    let verificationUri: String?
}

enum PiProviderAuthBridgeEvent: Sendable {
    case prompt(id: String, prompt: PiProviderAuthPrompt)
    case notification(PiProviderAuthNotification)
    case completed(success: Bool, error: String?)
}

enum PiProviderAuthBridgeError: LocalizedError {
    case piMissing
    case nodeMissing
    case bridgeMissing
    case invalidResponse
    case launchFailed(String)
    case bridgeFailed(String)

    var errorDescription: String? {
        switch self {
        case .piMissing:
            "Pi CLI is required to load login providers"
        case .nodeMissing:
            "Node.js is required for Pi provider login"
        case .bridgeMissing:
            "Pi provider login bridge is missing from this app"
        case .invalidResponse:
            "Pi returned an invalid provider list"
        case .launchFailed(let message), .bridgeFailed(let message):
            message
        }
    }
}

private struct PiProviderAuthBridgeEnvelope: Decodable {
    let type: String
    let providers: [PiLoginProvider]?
    let id: String?
    let prompt: PiProviderAuthPrompt?
    let event: PiProviderAuthNotification?
    let success: Bool?
    let error: String?
}

fileprivate struct PiProviderAuthBridgeConfiguration: Sendable {
    let nodeExecutable: String
    let piExecutable: String
    let scriptURL: URL
    let agentDirectory: URL
    let workingDirectory: URL
}

enum PiProviderAuthBridge {
    static func listProviders(
        agentDirectory: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<[PiLoginProvider], Error>) -> Void
    ) {
        if PersonalPiRuntimeEnvironment.isUITesting {
            completion(.success(uiTestProviders))
            return
        }

        let configuration: PiProviderAuthBridgeConfiguration
        do {
            configuration = try makeConfiguration(
                agentDirectory: agentDirectory,
                workingDirectory: workingDirectory
            )
        } catch {
            completion(.failure(error))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = URL(fileURLWithPath: configuration.nodeExecutable)
            process.arguments = [
                configuration.scriptURL.path,
                "list",
                configuration.piExecutable,
                configuration.workingDirectory.path
            ]
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            process.environment = environment(for: configuration)
            process.standardOutput = output
            process.standardError = error

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                completion(.failure(PiProviderAuthBridgeError.launchFailed(error.localizedDescription)))
                return
            }

            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            if let providers = try? decodeProviderList(outputData) {
                completion(.success(providers))
                return
            }
            if let message = decodeFailureMessage(outputData) {
                completion(.failure(PiProviderAuthBridgeError.bridgeFailed(message)))
                return
            }

            let stderr = String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(.failure(PiProviderAuthBridgeError.bridgeFailed(
                stderr?.nilIfEmpty ?? PiProviderAuthBridgeError.invalidResponse.localizedDescription
            )))
        }
    }

    static func makeLoginProcess(
        agentDirectory: URL,
        workingDirectory: URL
    ) throws -> PiProviderAuthLoginProcess {
        try PiProviderAuthLoginProcess(configuration: makeConfiguration(
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory
        ))
    }

    static func logoutProvider(
        agentDirectory: URL,
        workingDirectory: URL,
        providerID: String,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        runOneShot(
            mode: "logout",
            arguments: [providerID],
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory,
            completion: completion
        )
    }

    static func refreshModelCatalog(
        agentDirectory: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        runOneShot(
            mode: "refresh_models",
            arguments: [],
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory,
            completion: completion
        )
    }

    static func decodeProviderList(_ data: Data) throws -> [PiLoginProvider] {
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A).reversed() where !line.isEmpty {
            if let envelope = try? decoder.decode(PiProviderAuthBridgeEnvelope.self, from: Data(line)),
               envelope.type == "providers",
               let providers = envelope.providers {
                return providers
            }
        }
        throw PiProviderAuthBridgeError.invalidResponse
    }

    static func decodeEvent(_ data: Data) throws -> PiProviderAuthBridgeEvent {
        let envelope = try JSONDecoder().decode(PiProviderAuthBridgeEnvelope.self, from: data)
        switch envelope.type {
        case "prompt":
            guard let id = envelope.id, let prompt = envelope.prompt else {
                throw PiProviderAuthBridgeError.invalidResponse
            }
            return .prompt(id: id, prompt: prompt)
        case "notification":
            guard let event = envelope.event else {
                throw PiProviderAuthBridgeError.invalidResponse
            }
            return .notification(event)
        case "result":
            return .completed(success: envelope.success == true, error: envelope.error)
        default:
            throw PiProviderAuthBridgeError.invalidResponse
        }
    }

    static func decodeFailureMessage(_ data: Data) -> String? {
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A).reversed() where !line.isEmpty {
            guard let envelope = try? decoder.decode(
                PiProviderAuthBridgeEnvelope.self,
                from: Data(line)
            ) else { continue }
            if envelope.type == "result", envelope.success != true {
                return envelope.error?.nilIfEmpty
            }
        }
        return nil
    }

    static func decodeSuccessfulResult(_ data: Data) -> Bool {
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A).reversed() where !line.isEmpty {
            guard let envelope = try? decoder.decode(
                PiProviderAuthBridgeEnvelope.self,
                from: Data(line)
            ) else { continue }
            if envelope.type == "result" {
                return envelope.success == true
            }
        }
        return false
    }

    static var uiTestProviders: [PiLoginProvider] {
        [
            PiLoginProvider(
                id: "openai-codex",
                name: "OpenAI Codex",
                configured: true,
                configuredAuthType: .oauth,
                storedAuthType: .oauth,
                methods: [
                    PiProviderLoginMethod(
                        type: .oauth,
                        name: "OpenAI (ChatGPT Plus/Pro)",
                        loginLabel: nil,
                        interactive: true,
                        subscription: true
                    )
                ]
            ),
            PiLoginProvider(
                id: "deepseek",
                name: "DeepSeek",
                configured: true,
                configuredAuthType: .apiKey,
                storedAuthType: .apiKey,
                methods: [
                    PiProviderLoginMethod(
                        type: .apiKey,
                        name: "DeepSeek API key",
                        loginLabel: nil,
                        interactive: true,
                        subscription: false
                    )
                ]
            ),
            PiLoginProvider(
                id: "anthropic",
                name: "Anthropic",
                configured: false,
                configuredAuthType: nil,
                storedAuthType: nil,
                methods: [
                    PiProviderLoginMethod(
                        type: .oauth,
                        name: "Anthropic (Claude Pro/Max)",
                        loginLabel: nil,
                        interactive: true,
                        subscription: true
                    ),
                    PiProviderLoginMethod(
                        type: .apiKey,
                        name: "Anthropic API key",
                        loginLabel: nil,
                        interactive: true,
                        subscription: false
                    )
                ]
            )
        ]
    }

    fileprivate static func makeConfiguration(
        agentDirectory: URL,
        workingDirectory: URL
    ) throws -> PiProviderAuthBridgeConfiguration {
        guard let piExecutable = PiLaunchConfiguration.resolvedExecutable() else {
            throw PiProviderAuthBridgeError.piMissing
        }
        guard let nodeExecutable = PiLaunchConfiguration.resolvedNodeExecutable() else {
            throw PiProviderAuthBridgeError.nodeMissing
        }

        let bundled = Bundle.main.url(forResource: "pi-auth-bridge", withExtension: "mjs")
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/pi-auth-bridge.mjs")
        let scriptURL = bundled ?? (FileManager.default.fileExists(atPath: development.path) ? development : nil)
        guard let scriptURL else { throw PiProviderAuthBridgeError.bridgeMissing }

        return PiProviderAuthBridgeConfiguration(
            nodeExecutable: nodeExecutable,
            piExecutable: piExecutable,
            scriptURL: scriptURL,
            agentDirectory: agentDirectory.standardizedFileURL,
            workingDirectory: workingDirectory.standardizedFileURL
        )
    }

    fileprivate static func environment(
        for configuration: PiProviderAuthBridgeConfiguration
    ) -> [String: String] {
        var environment = PiLaunchConfiguration.processEnvironment()
        environment["PI_CODING_AGENT_DIR"] = configuration.agentDirectory.path
        return environment
    }

    private static func runOneShot(
        mode: String,
        arguments: [String],
        agentDirectory: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        if PersonalPiRuntimeEnvironment.isUITesting {
            completion(.success(()))
            return
        }

        let configuration: PiProviderAuthBridgeConfiguration
        do {
            configuration = try makeConfiguration(
                agentDirectory: agentDirectory,
                workingDirectory: workingDirectory
            )
        } catch {
            completion(.failure(error))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = URL(fileURLWithPath: configuration.nodeExecutable)
            process.arguments = [
                configuration.scriptURL.path,
                mode,
                configuration.piExecutable,
                configuration.workingDirectory.path
            ] + arguments
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            process.environment = environment(for: configuration)
            process.standardOutput = output
            process.standardError = error

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                completion(.failure(PiProviderAuthBridgeError.launchFailed(error.localizedDescription)))
                return
            }

            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            if decodeSuccessfulResult(outputData) {
                completion(.success(()))
                return
            }
            let stderr = String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(.failure(PiProviderAuthBridgeError.bridgeFailed(
                decodeFailureMessage(outputData)
                    ?? stderr?.nilIfEmpty
                    ?? PiProviderAuthBridgeError.invalidResponse.localizedDescription
            )))
        }
    }
}

final class PiProviderAuthLoginProcess: NSObject, @unchecked Sendable {
    private let configuration: PiProviderAuthBridgeConfiguration
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private let ioQueue = DispatchQueue(label: "dev.pi.personal.provider-auth")
    private var receivedResult = false

    var onEvent: (@Sendable (PiProviderAuthBridgeEvent) -> Void)?

    fileprivate init(configuration: PiProviderAuthBridgeConfiguration) {
        self.configuration = configuration
    }

    func start(providerID: String, authType: PiProviderAuthType) throws {
        guard process == nil else { return }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: configuration.nodeExecutable)
        process.arguments = [
            configuration.scriptURL.path,
            "login",
            configuration.piExecutable,
            configuration.workingDirectory.path,
            providerID,
            authType.rawValue
        ]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.environment = PiProviderAuthBridge.environment(for: configuration)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        self.process = process
        inputPipe = input
        outputPipe = output
        errorPipe = error

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.ioQueue.async { [weak self] in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self?.consumeOnQueue(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            self?.ioQueue.async { [weak self] in
                self?.handleTerminationOnQueue(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            cleanupOnQueue()
            throw PiProviderAuthBridgeError.launchFailed(error.localizedDescription)
        }
    }

    func respond(promptID: String, value: String) {
        ioQueue.async { [weak self] in
            self?.sendOnQueue(["type": "response", "id": promptID, "value": value])
        }
    }

    func cancelPrompt(promptID: String) {
        ioQueue.async { [weak self] in
            self?.sendOnQueue(["type": "response", "id": promptID, "cancelled": true])
        }
    }

    func cancel() {
        ioQueue.async { [self] in
            sendOnQueue(["type": "cancel"])
            process?.terminationHandler = nil
            process?.terminate()
            cleanupOnQueue()
        }
    }

    private func sendOnQueue(_ object: [String: Any]) {
        guard let inputPipe,
              let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        inputPipe.fileHandleForWriting.write(data)
        inputPipe.fileHandleForWriting.write(Data([0x0A]))
    }

    private func consumeOnQueue(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let event = try? PiProviderAuthBridge.decodeEvent(Data(line)) else { continue }

            if case .completed = event {
                receivedResult = true
            }
            onEvent?(event)
        }
    }

    private func handleTerminationOnQueue(status: Int32) {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        if let remaining = outputPipe?.fileHandleForReading.readDataToEndOfFile(),
           !remaining.isEmpty {
            consumeOnQueue(remaining)
        }

        if !receivedResult {
            let stderr = errorPipe.flatMap {
                String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = stderr?.nilIfEmpty ?? "Pi provider login ended unexpectedly (status \(status))"
            onEvent?(.completed(success: false, error: message))
        }
        cleanupOnQueue()
    }

    private func cleanupOnQueue() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        outputBuffer.removeAll(keepingCapacity: false)
    }

    deinit {
        process?.terminate()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
