import Foundation
import Darwin

enum KnowledgeLibraryScope: String, CaseIterable, Identifiable, Sendable {
    case global
    case project

    var id: String { rawValue }
}

struct KnowledgeScopeInfo: Codable, Sendable, Hashable {
    let id: String
    let kind: String
    let knowledgeRoot: String
    let projectRoot: String?
    let indexPath: String
}

struct KnowledgeCategorySummary: Codable, Sendable, Hashable {
    let files: Int
    let bytes: Int64
}

struct KnowledgeFileIndex: Codable, Sendable, Hashable {
    let documentId: String
    let title: String
    let status: String
    let chunks: Int
    let error: String?
    var stale: Bool? = nil
}

struct KnowledgeFileEntry: Codable, Sendable, Hashable, Identifiable {
    let relativePath: String
    let category: String
    let name: String
    let `extension`: String
    let sizeBytes: Int64
    let modifiedAt: String
    let supported: Bool
    let index: KnowledgeFileIndex?

    var id: String { relativePath }

    var modifiedDate: Date? {
        KnowledgeFormat.date(modifiedAt)
    }
}

struct KnowledgeLatestRun: Codable, Sendable, Hashable {
    let id: String
    let action: String
    let finishedAt: String

    enum CodingKeys: String, CodingKey {
        case id, action
        case finishedAt = "finished_at"
    }

    var date: Date? {
        KnowledgeFormat.date(finishedAt)
    }
}

struct KnowledgeInventoryResponse: Codable, Sendable, Hashable {
    let success: Bool
    let scope: KnowledgeScopeInfo
    let initialized: Bool
    let fileCount: Int
    let totalBytes: Int64
    let categories: [String: KnowledgeCategorySummary]
    let files: [KnowledgeFileEntry]
    let truncated: Bool
    let latestRun: KnowledgeLatestRun?
}

struct KnowledgeIndexFailure: Codable, Sendable, Hashable {
    let path: String
    let error: String
}

struct KnowledgeIndexResponse: Codable, Sendable, Hashable {
    let success: Bool?
    let scope: KnowledgeScopeInfo
    let runId: String
    let action: String
    let indexed: Int
    let updated: Int
    let unchanged: Int
    let removed: Int
    let failed: Int
    let failures: [KnowledgeIndexFailure]
}

struct KnowledgeSearchDocument: Codable, Sendable, Hashable {
    let id: String
    let relativePath: String
    let category: String
    let title: String
    let status: String
    let confidence: String?
    var contentHash: String? = nil
}

struct KnowledgeSearchChunk: Codable, Sendable, Hashable {
    let id: String
    let locator: String
    let heading: String?
    let pageNumber: Int?
    let text: String
}

struct KnowledgeSearchHit: Codable, Sendable, Hashable, Identifiable {
    let score: Double
    let document: KnowledgeSearchDocument
    let chunk: KnowledgeSearchChunk

    var id: String { "\(document.id):\(chunk.id)" }
}

struct KnowledgeSearchResponse: Codable, Sendable, Hashable {
    let success: Bool
    let query: String
    let results: [KnowledgeSearchHit]
    let scopes: [KnowledgeSearchScopeState]
}

struct KnowledgeSearchScopeState: Codable, Sendable, Hashable {
    let scope: KnowledgeScopeInfo
    let initialized: Bool
    let error: String?
}

struct KnowledgeDocumentResponse: Decodable, Sendable {
    let document: KnowledgeSearchDocument
    let chunks: [KnowledgeSearchChunk]
    var recoveryPath: String? = nil
}

struct KnowledgeImportResponse: Decodable, Sendable {
    let imported: [String]
    let failures: [KnowledgeIndexFailure]
    let index: KnowledgeIndexResponse?
}

enum KnowledgeCoreClientError: LocalizedError {
    case runtimeMissing
    case uvMissing
    case launchFailed(String)
    case operationFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            "Bundled Knowledge runtime is missing"
        case .uvMissing:
            "uv is required to prepare the Knowledge runtime"
        case .launchFailed(let detail):
            "Unable to start Knowledge runtime: \(detail)"
        case .operationFailed(let detail):
            detail
        case .invalidResponse:
            "Knowledge runtime returned an invalid response"
        }
    }
}

struct KnowledgeScopePayload: Codable, Sendable {
    let kind: String
    let projectRoot: String?
}

struct KnowledgeCoreRequest: Encodable, Sendable {
    let action: String
    let piRoot: String
    let scope: KnowledgeScopePayload?
    let scopes: [KnowledgeScopePayload]?
    let query: String?
    let limit: Int?
    var documentId: String? = nil
    var userConfirmed: Bool? = nil
    var expectedContentHash: String? = nil
    var paths: [String]? = nil
}

private struct KnowledgeCoreEnvelope: Decodable {
    let success: Bool
    let error: String?
}

private struct KnowledgeCoreConfiguration: Sendable {
    let uvExecutable: String
    let runnerURL: URL
    let pyprojectURL: URL
    let lockURL: URL
    let environmentURL: URL
    let workingDirectory: URL
}

enum KnowledgeCoreClient {
    private static let prepared = PiPreparedEnvironments()
    private static let queue = DispatchQueue(
        label: "dev.pi.personal.knowledge-core",
        qos: .userInitiated
    )
    private static let literatureQueue = DispatchQueue(label: "dev.pi.personal.literature", qos: .userInitiated)

    static func inventory(
        scope: KnowledgeLibraryScope,
        piRoot: URL,
        projectRoot: URL?,
        completion: @escaping @Sendable (Result<KnowledgeInventoryResponse, Error>) -> Void
    ) {
        let payload = scopePayload(scope, projectRoot: projectRoot)
        perform(
            request: KnowledgeCoreRequest(
                action: "inventory",
                piRoot: piRoot.path,
                scope: payload,
                scopes: nil,
                query: nil,
                limit: 1_000
            ),
            piRoot: piRoot,
            workingDirectory: projectRoot ?? piRoot.appendingPathComponent("chat", isDirectory: true),
            completion: completion
        )
    }

    static func index(
        scope: KnowledgeLibraryScope,
        rebuild: Bool,
        piRoot: URL,
        projectRoot: URL?,
        completion: @escaping @Sendable (Result<KnowledgeIndexResponse, Error>) -> Void
    ) {
        let payload = scopePayload(scope, projectRoot: projectRoot)
        perform(
            request: KnowledgeCoreRequest(
                action: rebuild ? "rebuild" : "index",
                piRoot: piRoot.path,
                scope: payload,
                scopes: nil,
                query: nil,
                limit: nil
            ),
            piRoot: piRoot,
            workingDirectory: projectRoot ?? piRoot.appendingPathComponent("chat", isDirectory: true),
            completion: completion
        )
    }

    static func search(
        query: String,
        scope: KnowledgeLibraryScope,
        piRoot: URL,
        projectRoot: URL?,
        completion: @escaping @Sendable (Result<KnowledgeSearchResponse, Error>) -> Void
    ) {
        let payload = scopePayload(scope, projectRoot: projectRoot)
        perform(
            request: KnowledgeCoreRequest(
                action: "search",
                piRoot: piRoot.path,
                scope: nil,
                scopes: [payload],
                query: query,
                limit: 50
            ),
            piRoot: piRoot,
            workingDirectory: projectRoot ?? piRoot.appendingPathComponent("chat", isDirectory: true),
            completion: completion
        )
    }

    static func decodeInventory(_ data: Data) throws -> KnowledgeInventoryResponse {
        try decode(KnowledgeInventoryResponse.self, from: data)
    }

    static func decodeIndex(_ data: Data) throws -> KnowledgeIndexResponse {
        try decode(KnowledgeIndexResponse.self, from: data)
    }

    static func decodeSearch(_ data: Data) throws -> KnowledgeSearchResponse {
        try decode(KnowledgeSearchResponse.self, from: data)
    }

    private static func scopePayload(
        _ scope: KnowledgeLibraryScope,
        projectRoot: URL?
    ) -> KnowledgeScopePayload {
        KnowledgeScopePayload(
            kind: scope.rawValue,
            projectRoot: scope == .project ? projectRoot?.path : nil
        )
    }

    private static func perform<Response: Decodable & Sendable>(
        request: KnowledgeCoreRequest,
        piRoot: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Response, Error>) -> Void
    ) {
        execute(request: request, piRoot: piRoot, workingDirectory: workingDirectory) { result in
            completion(result.flatMap { data in
                Result { try decode(Response.self, from: data) }
            })
        }
    }

    static func execute(
        request: KnowledgeCoreRequest,
        piRoot: URL,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        queue.async {
            do {
                if PersonalPiRuntimeEnvironment.isUITesting {
                    let scope = request.scope?.kind ?? request.scopes?.first?.kind ?? "global"
                    let fixture = piRoot.appendingPathComponent("ui-fixtures/\(request.action)-\(scope).json")
                    completion(.success(try Data(contentsOf: fixture)))
                    return
                }
                let configuration = try makeConfiguration(piRoot: piRoot, workingDirectory: workingDirectory)
                let pythonURL = try prepareEnvironment(configuration)
                let requestData = try JSONEncoder().encode(request)
                let output = try runProcess(
                    executable: pythonURL,
                    arguments: [configuration.runnerURL.path],
                    input: requestData,
                    workingDirectory: configuration.workingDirectory
                )
                completion(.success(output))
            } catch {
                prepared.remove(PiRuntimeContext(dataRoot: piRoot).knowledgeEnvironment)
                completion(.failure(error))
            }
        }
    }

    /// Trusted bundled adapter, sharing Knowledge's environment and subprocess
    /// boundary without exposing a script path to View or model arguments.
    static func executeLiterature(
        request: LiteratureRequest,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        literatureQueue.async {
            do {
                let root = URL(fileURLWithPath: request.piRoot)
                if PersonalPiRuntimeEnvironment.isUITesting {
                    completion(.success(try Data(contentsOf: root.appendingPathComponent("ui-fixtures/literature-\(request.action).json"))))
                    return
                }
                guard let package = PiLaunchConfiguration.bundledPlugins.first(where: { $0.id == "literature" }) else {
                    throw KnowledgeCoreClientError.runtimeMissing
                }
                let configuration = try makeConfiguration(piRoot: root, workingDirectory: URL(fileURLWithPath: request.cwd))
                // Environment setup remains serialized with Knowledge, while
                // remote search must not block local inventory and retrieval.
                let python = try queue.sync { try prepareEnvironment(configuration) }
                completion(.success(try runProcess(executable: python,
                    arguments: [package.rootURL.appendingPathComponent("runtime/literature.py").path],
                    input: JSONEncoder().encode(request), workingDirectory: configuration.workingDirectory)))
            } catch { completion(.failure(error)) }
        }
    }

    private static func makeConfiguration(
        piRoot: URL,
        workingDirectory: URL
    ) throws -> KnowledgeCoreConfiguration {
        guard let packageURL = PiLaunchConfiguration.knowledgePluginPackageURL else {
            throw KnowledgeCoreClientError.runtimeMissing
        }
        guard let uvExecutable = PiLaunchConfiguration.resolvedUvExecutable() else {
            throw KnowledgeCoreClientError.uvMissing
        }
        let runtimeURL = packageURL.appendingPathComponent("runtime", isDirectory: true)
        let runnerURL = runtimeURL.appendingPathComponent("knowledge_core.py")
        let pyprojectURL = runtimeURL.appendingPathComponent("pyproject.toml")
        let lockURL = runtimeURL.appendingPathComponent("uv.lock")
        guard [runnerURL, pyprojectURL, lockURL].allSatisfy({
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw KnowledgeCoreClientError.runtimeMissing
        }
        return KnowledgeCoreConfiguration(
            uvExecutable: uvExecutable,
            runnerURL: runnerURL,
            pyprojectURL: pyprojectURL,
            lockURL: lockURL,
            environmentURL: PiRuntimeContext(dataRoot: piRoot).knowledgeEnvironment,
            workingDirectory: workingDirectory
        )
    }

    private static func prepareEnvironment(_ configuration: KnowledgeCoreConfiguration) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: configuration.environmentURL,
            withIntermediateDirectories: true
        )
        let projectDestination = configuration.environmentURL.appendingPathComponent("pyproject.toml")
        let lockDestination = configuration.environmentURL.appendingPathComponent("uv.lock")
        let projectChanged = try copyIfChanged(configuration.pyprojectURL, to: projectDestination)
        let lockChanged = try copyIfChanged(configuration.lockURL, to: lockDestination)
        let pythonURL = configuration.environmentURL.appendingPathComponent(".venv/bin/python")
        if !projectChanged, !lockChanged, prepared.contains(configuration.environmentURL),
           fileManager.isExecutableFile(atPath: pythonURL.path) {
            return pythonURL
        }
        _ = try runProcess(
                executable: URL(fileURLWithPath: configuration.uvExecutable),
                arguments: [
                    "sync", "--project", configuration.environmentURL.path,
                    "--locked", "--no-progress",
                ],
                input: nil,
                workingDirectory: configuration.workingDirectory,
                extraEnvironment: [
                    "UV_NO_PROGRESS": "1",
                    "UV_PROJECT_ENVIRONMENT": configuration.environmentURL.appendingPathComponent(".venv").path,
                ]
            )
        guard fileManager.isExecutableFile(atPath: pythonURL.path) else {
            throw KnowledgeCoreClientError.operationFailed(
                "Knowledge Python environment was not created"
            )
        }
        prepared.insert(configuration.environmentURL)
        return pythonURL
    }

    private static func copyIfChanged(_ source: URL, to destination: URL) throws -> Bool {
        let data = try Data(contentsOf: source)
        if let existing = try? Data(contentsOf: destination), existing == data {
            return false
        }
        try data.write(to: destination, options: .atomic)
        return true
    }

    private static func runProcess(
        executable: URL,
        arguments: [String],
        input: Data?,
        workingDirectory: URL,
        extraEnvironment: [String: String] = [:]
    ) throws -> Data {
        var environment = PiLaunchConfiguration.processEnvironment()
        extraEnvironment.forEach { environment[$0.key] = $0.value }
        environment["PYTHONUNBUFFERED"] = "1"
        let captured = try PiProcessRunner.run(executable: executable, arguments: arguments,
            workingDirectory: workingDirectory, environment: environment, input: input)
        guard captured.status == 0 else {
            let detail = String(data: captured.error, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw KnowledgeCoreClientError.operationFailed(detail?.isEmpty == false ? detail! : "Knowledge process failed")
        }
        return captured.output
    }

    static func decode<Response: Decodable>(
        _ type: Response.Type,
        from data: Data
    ) throws -> Response {
        guard let line = data.split(separator: 0x0A).last(where: { !$0.isEmpty }) else {
            throw KnowledgeCoreClientError.invalidResponse
        }
        let payload = Data(line)
        let envelope = try JSONDecoder().decode(KnowledgeCoreEnvelope.self, from: payload)
        guard envelope.success else {
            throw KnowledgeCoreClientError.operationFailed(
                envelope.error ?? KnowledgeCoreClientError.invalidResponse.localizedDescription
            )
        }
        return try JSONDecoder().decode(type, from: payload)
    }
}

enum KnowledgeFormat {
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: value)
    }
}
