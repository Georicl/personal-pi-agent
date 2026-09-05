import Foundation

/// One path contract for the GUI, Pi RPC and one-shot bridges.
struct PiRuntimeContext: Sendable, Equatable {
    let piRoot: URL
    let agentDirectory: URL
    let knowledgeEnvironment: URL

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         home: URL = FileManager.default.homeDirectoryForCurrentUser, dataRoot: URL? = nil) {
        func path(_ key: String) -> URL? {
            guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            let expanded = value == "~" ? home.path
                : value.hasPrefix("~/") ? home.appendingPathComponent(String(value.dropFirst(2))).path : value
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }
        let agent = path("PI_CODING_AGENT_DIR")
        piRoot = (dataRoot ?? path("PERSONAL_PI_DATA_ROOT") ?? agent?.deletingLastPathComponent()
                  ?? home.appendingPathComponent(".pi", isDirectory: true)).standardizedFileURL
        agentDirectory = agent ?? piRoot.appendingPathComponent("agent", isDirectory: true)
        knowledgeEnvironment = path("PERSONAL_PI_KNOWLEDGE_ENVIRONMENT")
            ?? agentDirectory.appendingPathComponent("environments/knowledge", isDirectory: true)
    }

    static var current: PiRuntimeContext { PiRuntimeContext() }
    var settingsURL: URL { agentDirectory.appendingPathComponent("settings.json") }
    var sessionsURL: URL { agentDirectory.appendingPathComponent("sessions", isDirectory: true) }

    func processEnvironment(_ inherited: [String: String]) -> [String: String] {
        var result = inherited
        result["PERSONAL_PI_DATA_ROOT"] = piRoot.path
        result["PI_CODING_AGENT_DIR"] = agentDirectory.path
        result["PERSONAL_PI_KNOWLEDGE_ENVIRONMENT"] = knowledgeEnvironment.path
        return result
    }
}
