import Foundation

enum PiPackageScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case user
    case project

    var id: String { rawValue }
}

enum PiResourceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case extensions
    case skills
    case prompts
    case themes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extensions: "Extensions"
        case .skills: "Skills"
        case .prompts: "Prompt Templates"
        case .themes: "Themes"
        }
    }

    var icon: String {
        switch self {
        case .extensions: "puzzlepiece.extension"
        case .skills: "wand.and.stars"
        case .prompts: "text.bubble"
        case .themes: "paintpalette"
        }
    }
}

enum PiResourceOrigin: String, Codable, Sendable {
    case package
    case topLevel = "top-level"
}

enum PiResourceOverrideState: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit
    case load
    case unload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inherit: "Inherit"
        case .load: "Enabled"
        case .unload: "Disabled"
        }
    }
}

struct PiConfiguredPackage: Codable, Identifiable, Sendable, Hashable {
    let source: String
    let scope: PiPackageScope
    let filtered: Bool
    let installedPath: String?

    var id: String { "\(scope.rawValue):\(source)" }
    var isInstalled: Bool { installedPath != nil }
}

struct PiPackageResource: Codable, Identifiable, Sendable, Hashable {
    let resourceType: PiResourceType
    let path: String
    let enabled: Bool
    let source: String
    let sourceScope: PiPackageScope
    let origin: PiResourceOrigin
    let baseDir: String?
    let name: String
    let inherited: Bool
    let overrideState: PiResourceOverrideState

    var id: String {
        "\(resourceType.rawValue):\(origin.rawValue):\(sourceScope.rawValue):\(source):\(path)"
    }
}

struct PiResourcePathConfiguration: Codable, Sendable, Hashable {
    var extensions: [String]
    var skills: [String]
    var prompts: [String]
    var themes: [String]

    static let empty = PiResourcePathConfiguration(
        extensions: [],
        skills: [],
        prompts: [],
        themes: []
    )

    subscript(type: PiResourceType) -> [String] {
        get {
            switch type {
            case .extensions: extensions
            case .skills: skills
            case .prompts: prompts
            case .themes: themes
            }
        }
        set {
            switch type {
            case .extensions: extensions = newValue
            case .skills: skills = newValue
            case .prompts: prompts = newValue
            case .themes: themes = newValue
            }
        }
    }
}

struct PiPackageSnapshot: Codable, Sendable {
    let packages: [PiConfiguredPackage]
    let globalResources: [PiPackageResource]
    let projectResources: [PiPackageResource]
    let globalConfiguredPaths: PiResourcePathConfiguration
    let projectConfiguredPaths: PiResourcePathConfiguration
    let errors: [String]

    static let empty = PiPackageSnapshot(
        packages: [],
        globalResources: [],
        projectResources: [],
        globalConfiguredPaths: .empty,
        projectConfiguredPaths: .empty,
        errors: []
    )
}

enum PiPackageBridgeError: LocalizedError {
    case piMissing
    case nodeMissing
    case bridgeMissing
    case invalidResponse
    case launchFailed(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .piMissing:
            "Pi CLI is required to manage packages"
        case .nodeMissing:
            "Node.js is required to manage Pi packages"
        case .bridgeMissing:
            "Pi package bridge is missing from this app"
        case .invalidResponse:
            "Pi returned an invalid package response"
        case .launchFailed(let message), .operationFailed(let message):
            message
        }
    }
}

private struct PiPackageBridgeEnvelope: Decodable {
    let type: String
    let packages: [PiConfiguredPackage]?
    let globalResources: [PiPackageResource]?
    let projectResources: [PiPackageResource]?
    let globalConfiguredPaths: PiResourcePathConfiguration?
    let projectConfiguredPaths: PiResourcePathConfiguration?
    let errors: [String]?
    let success: Bool?
    let error: String?
}

private struct PiPackageBridgeConfiguration: Sendable {
    let nodeExecutable: String
    let piExecutable: String
    let scriptURL: URL
    let agentDirectory: URL
    let workingDirectory: URL
}

private struct PiPackageSourcePayload: Encodable {
    let source: String?
    let scope: PiPackageScope?
}

private struct PiPackageResourcePayload: Encodable {
    let scope: PiPackageScope
    let desiredState: PiResourceOverrideState
    let resource: PiPackageResource
}

private struct PiPackagePathsPayload: Encodable {
    let scope: PiPackageScope
    let paths: PiResourcePathConfiguration
}

enum PiPackageBridge {
    static func load(
        agentDirectory: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<PiPackageSnapshot, Error>) -> Void
    ) {
        if PersonalPiRuntimeEnvironment.isUITesting {
            completion(.success(uiTestSnapshot))
            return
        }
        run(
            mode: "list",
            payload: Optional<PiPackageSourcePayload>.none,
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory
        ) { dataResult in
            completion(dataResult.flatMap { data in
                do { return .success(try decodeSnapshot(data)) }
                catch { return .failure(error) }
            })
        }
    }

    static func install(
        source: String,
        scope: PiPackageScope,
        agentDirectory: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        runOperation(
            mode: "install",
            payload: PiPackageSourcePayload(source: source, scope: scope),
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory,
            completion: completion
        )
    }

    static func remove(
        source: String,
        scope: PiPackageScope,
        agentDirectory: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        runOperation(
            mode: "remove",
            payload: PiPackageSourcePayload(source: source, scope: scope),
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory,
            completion: completion
        )
    }

    static func update(
        source: String?,
        agentDirectory: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        runOperation(
            mode: "update",
            payload: PiPackageSourcePayload(source: source, scope: nil),
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory,
            completion: completion
        )
    }

    static func setResource(
        _ resource: PiPackageResource,
        scope: PiPackageScope,
        state: PiResourceOverrideState,
        agentDirectory: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        runOperation(
            mode: "set_resource",
            payload: PiPackageResourcePayload(
                scope: scope,
                desiredState: state,
                resource: resource
            ),
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory,
            completion: completion
        )
    }

    static func setConfiguredPaths(
        _ paths: PiResourcePathConfiguration,
        scope: PiPackageScope,
        agentDirectory: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        runOperation(
            mode: "set_paths",
            payload: PiPackagePathsPayload(scope: scope, paths: paths),
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory,
            completion: completion
        )
    }

    static func decodeSnapshot(_ data: Data) throws -> PiPackageSnapshot {
        let envelope = try decodeLastEnvelope(data)
        if envelope.type == "result", envelope.success != true, let error = envelope.error {
            throw PiPackageBridgeError.operationFailed(error)
        }
        guard envelope.type == "snapshot",
              let packages = envelope.packages,
              let globalResources = envelope.globalResources,
              let projectResources = envelope.projectResources,
              let globalConfiguredPaths = envelope.globalConfiguredPaths,
              let projectConfiguredPaths = envelope.projectConfiguredPaths else {
            throw PiPackageBridgeError.invalidResponse
        }
        return PiPackageSnapshot(
            packages: packages,
            globalResources: globalResources,
            projectResources: projectResources,
            globalConfiguredPaths: globalConfiguredPaths,
            projectConfiguredPaths: projectConfiguredPaths,
            errors: envelope.errors ?? []
        )
    }

    static var uiTestSnapshot: PiPackageSnapshot {
        let extensionResource = PiPackageResource(
            resourceType: .extensions,
            path: "/tmp/personal-pi-test/extensions/example.ts",
            enabled: true,
            source: "npm:personal-pi-example",
            sourceScope: .user,
            origin: .package,
            baseDir: "/tmp/personal-pi-test",
            name: "example.ts",
            inherited: false,
            overrideState: .load
        )
        return PiPackageSnapshot(
            packages: [
                PiConfiguredPackage(
                    source: "npm:personal-pi-example",
                    scope: .user,
                    filtered: false,
                    installedPath: "/tmp/personal-pi-test"
                )
            ],
            globalResources: [extensionResource],
            projectResources: [extensionResource],
            globalConfiguredPaths: PiResourcePathConfiguration(
                extensions: ["extensions/*.ts"],
                skills: [],
                prompts: [],
                themes: []
            ),
            projectConfiguredPaths: .empty,
            errors: []
        )
    }

    private static func runOperation<Payload: Encodable>(
        mode: String,
        payload: Payload,
        agentDirectory: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        if PersonalPiRuntimeEnvironment.isUITesting {
            completion(.success(()))
            return
        }
        run(
            mode: mode,
            payload: payload,
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory
        ) { result in
            completion(result.flatMap { data in
                do {
                    let envelope = try decodeLastEnvelope(data)
                    if envelope.type == "result", envelope.success == true {
                        return .success(())
                    }
                    return .failure(PiPackageBridgeError.operationFailed(
                        envelope.error ?? PiPackageBridgeError.invalidResponse.localizedDescription
                    ))
                } catch {
                    return .failure(error)
                }
            })
        }
    }

    private static func run<Payload: Encodable>(
        mode: String,
        payload: Payload?,
        agentDirectory: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        let configuration: PiPackageBridgeConfiguration
        do {
            configuration = try makeConfiguration(
                agentDirectory: agentDirectory,
                workingDirectory: workingDirectory
            )
        } catch {
            completion(.failure(error))
            return
        }

        let encodedPayload: String
        do {
            encodedPayload = try payload.map {
                try JSONEncoder().encode($0).base64EncodedString()
            } ?? ""
        } catch {
            completion(.failure(error))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var environment = PiLaunchConfiguration.processEnvironment()
            environment["PI_CODING_AGENT_DIR"] = configuration.agentDirectory.path
            let captured: PiProcessResult
            do {
                captured = try PiProcessRunner.run(
                    executable: URL(fileURLWithPath: configuration.nodeExecutable),
                    arguments: [configuration.scriptURL.path, mode, configuration.piExecutable,
                                configuration.workingDirectory.path, encodedPayload],
                    workingDirectory: FileManager.default.temporaryDirectory,
                    environment: environment, timeout: 600)
            } catch {
                completion(.failure(error))
                return
            }
            if !captured.output.isEmpty {
                completion(.success(captured.output))
                return
            }
            let stderr = String(
                data: captured.error,
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(.failure(PiPackageBridgeError.operationFailed(
                (stderr?.isEmpty == false ? stderr : nil)
                    ?? PiPackageBridgeError.invalidResponse.localizedDescription
            )))
        }
    }

    private static func decodeLastEnvelope(_ data: Data) throws -> PiPackageBridgeEnvelope {
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A).reversed() where !line.isEmpty {
            if let envelope = try? decoder.decode(PiPackageBridgeEnvelope.self, from: Data(line)) {
                return envelope
            }
        }
        throw PiPackageBridgeError.invalidResponse
    }

    private static func makeConfiguration(
        agentDirectory: URL,
        workingDirectory: URL
    ) throws -> PiPackageBridgeConfiguration {
        guard let piExecutable = PiLaunchConfiguration.resolvedExecutable() else {
            throw PiPackageBridgeError.piMissing
        }
        guard let nodeExecutable = PiLaunchConfiguration.resolvedNodeExecutable() else {
            throw PiPackageBridgeError.nodeMissing
        }
        let bundled = Bundle.main.url(forResource: "pi-package-bridge", withExtension: "mjs")
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/pi-package-bridge.mjs")
        let scriptURL = bundled ?? (FileManager.default.fileExists(atPath: development.path) ? development : nil)
        guard let scriptURL else { throw PiPackageBridgeError.bridgeMissing }

        return PiPackageBridgeConfiguration(
            nodeExecutable: nodeExecutable,
            piExecutable: piExecutable,
            scriptURL: scriptURL,
            agentDirectory: agentDirectory.standardizedFileURL,
            workingDirectory: workingDirectory.standardizedFileURL
        )
    }
}
