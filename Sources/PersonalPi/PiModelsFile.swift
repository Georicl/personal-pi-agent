import Foundation

enum PiModelAPI: String, CaseIterable, Identifiable, Sendable {
    case openAICompletions = "openai-completions"
    case openAIResponses = "openai-responses"
    case anthropicMessages = "anthropic-messages"
    case googleGenerativeAI = "google-generative-ai"

    var id: String { rawValue }
}

enum PiProviderCredentialSource: String, CaseIterable, Identifiable, Sendable {
    case piLogin
    case environment
    case localPlaceholder

    var id: String { rawValue }
}

struct PiCustomProviderDraft: Sendable, Equatable {
    var providerID = ""
    var baseURL = ""
    var api: PiModelAPI = .openAICompletions
    var credentialSource: PiProviderCredentialSource = .piLogin
    var environmentVariable = ""
    var modelID = ""
    var modelName = ""
    var reasoning = false
    var supportsImages = false
    var authHeader = false
    var contextWindow = ""
    var maxTokens = ""

    var normalizedProviderID: String {
        providerID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedModelID: String {
        modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func providerDocument() throws -> [String: Any] {
        let providerID = normalizedProviderID
        guard !providerID.isEmpty else { throw PiModelsFileError.providerIDRequired }
        guard Self.isValidProviderID(providerID) else { throw PiModelsFileError.invalidProviderID }

        let endpoint = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { throw PiModelsFileError.baseURLRequired }
        guard let components = URLComponents(string: endpoint),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else {
            throw PiModelsFileError.invalidBaseURL
        }

        let modelID = normalizedModelID
        guard !modelID.isEmpty else { throw PiModelsFileError.modelIDRequired }

        let contextWindow = try Self.positiveInteger(
            contextWindow,
            error: .invalidContextWindow
        )
        let maxTokens = try Self.positiveInteger(
            maxTokens,
            error: .invalidMaxTokens
        )

        var model: [String: Any] = [
            "id": modelID,
            "reasoning": reasoning,
            "input": supportsImages ? ["text", "image"] : ["text"]
        ]
        let modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !modelName.isEmpty { model["name"] = modelName }
        if let contextWindow { model["contextWindow"] = contextWindow }
        if let maxTokens { model["maxTokens"] = maxTokens }

        var provider: [String: Any] = [
            "baseUrl": endpoint,
            "api": api.rawValue,
            "models": [model]
        ]
        switch credentialSource {
        case .piLogin:
            break
        case .environment:
            provider["apiKey"] = try Self.environmentReference(environmentVariable)
        case .localPlaceholder:
            provider["apiKey"] = "local"
        }
        if authHeader { provider["authHeader"] = true }
        return provider
    }

    private static func isValidProviderID(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              isASCIIAlphaNumeric(first) || first == "_" else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            isASCIIAlphaNumeric($0) || $0 == "_" || $0 == "-" || $0 == "."
        }
    }

    private static func environmentReference(_ raw: String) throws -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("${"), name.hasSuffix("}"), name.count > 3 {
            name = String(name.dropFirst(2).dropLast())
        } else if name.hasPrefix("$") {
            name = String(name.dropFirst())
        }

        guard let first = name.unicodeScalars.first,
              isASCIIAlpha(first) || first == "_",
              name.unicodeScalars.allSatisfy({ isASCIIAlphaNumeric($0) || $0 == "_" }) else {
            throw PiModelsFileError.invalidEnvironmentVariable
        }
        return "$\(name)"
    }

    private static func positiveInteger(
        _ raw: String,
        error: PiModelsFileError
    ) throws -> Int? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let integer = Int(value), integer > 0 else { throw error }
        return integer
    }

    private static func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private static func isASCIIAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        isASCIIAlpha(scalar) || (48...57).contains(scalar.value)
    }
}

struct PiModelsCatalogSummary: Equatable, Sendable {
    let providerCount: Int
    let modelCount: Int
}

enum PiModelsFileError: LocalizedError, Equatable {
    case invalidRoot
    case invalidProviders
    case providerIDRequired
    case invalidProviderID
    case duplicateProvider
    case baseURLRequired
    case invalidBaseURL
    case modelIDRequired
    case invalidEnvironmentVariable
    case invalidContextWindow
    case invalidMaxTokens
    case invalidJSONValue

    var errorDescription: String? {
        switch self {
        case .invalidRoot: "Models file root must be a JSON object"
        case .invalidProviders: "The providers entry in models.json must be a JSON object"
        case .providerIDRequired: "Provider ID is required"
        case .invalidProviderID: "Provider ID may contain letters, numbers, dots, underscores and hyphens"
        case .duplicateProvider: "A provider with this ID already exists"
        case .baseURLRequired: "Base URL is required"
        case .invalidBaseURL: "Base URL must be a valid HTTP or HTTPS address"
        case .modelIDRequired: "Model ID is required"
        case .invalidEnvironmentVariable: "Enter a valid environment variable name"
        case .invalidContextWindow: "Context window must be a positive integer"
        case .invalidMaxTokens: "Maximum output tokens must be a positive integer"
        case .invalidJSONValue: "Models configuration contains an invalid JSON value"
        }
    }
}

enum PiModelsFile {
    static func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PiModelsFileError.invalidRoot
        }
        return object
    }

    @discardableResult
    static func add(_ draft: PiCustomProviderDraft, to url: URL) throws -> PiModelsCatalogSummary {
        let provider = try draft.providerDocument()
        var document = try read(url)
        var providers: [String: Any]
        if let existing = document["providers"] {
            guard let existing = existing as? [String: Any] else {
                throw PiModelsFileError.invalidProviders
            }
            providers = existing
        } else {
            providers = [:]
        }

        guard providers[draft.normalizedProviderID] == nil else {
            throw PiModelsFileError.duplicateProvider
        }
        providers[draft.normalizedProviderID] = provider
        document["providers"] = providers
        try write(document, to: url)
        return try summary(of: document)
    }

    static func summary(at url: URL) throws -> PiModelsCatalogSummary {
        try summary(of: read(url))
    }

    private static func summary(of document: [String: Any]) throws -> PiModelsCatalogSummary {
        guard let providerValue = document["providers"] else {
            return PiModelsCatalogSummary(providerCount: 0, modelCount: 0)
        }
        guard let providers = providerValue as? [String: Any] else {
            throw PiModelsFileError.invalidProviders
        }
        let modelCount = providers.values.reduce(into: 0) { count, value in
            guard let provider = value as? [String: Any],
                  let models = provider["models"] as? [Any] else { return }
            count += models.count
        }
        return PiModelsCatalogSummary(providerCount: providers.count, modelCount: modelCount)
    }

    private static func write(_ object: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw PiModelsFileError.invalidJSONValue
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}
