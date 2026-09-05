import Foundation
import Combine

enum PiSettingsScope: String, CaseIterable, Identifiable {
    case global = "Global"
    case project = "Project"
    case effective = "Effective"

    var id: String { rawValue }
}

enum PiOptionalSetting: String, CaseIterable, Identifiable {
    case inherited
    case enabled
    case disabled

    var id: String { rawValue }
}

@MainActor
final class PiSettingsEditor: ObservableObject {
    private(set) var contextID = UUID()
    @Published var selectedScope: PiSettingsScope = .global
    @Published var baseDocument: [String: Any] = [:]
    @Published var globalDocument: [String: Any] = [:]
    @Published var projectDocument: [String: Any] = [:]
    @Published var provider = ""
    @Published var model = ""
    @Published var thinkingLevel = ""
    @Published var enabledModels = ""
    @Published var modelThinkingLevels: [String: String] = [:]
    @Published var thinkingBudgetMinimal = ""
    @Published var thinkingBudgetLow = ""
    @Published var thinkingBudgetMedium = ""
    @Published var thinkingBudgetHigh = ""
    @Published var theme = ""
    @Published var compaction = PiOptionalSetting.inherited
    @Published var compactionReserveTokens = ""
    @Published var compactionKeepRecentTokens = ""
    @Published var retry = PiOptionalSetting.inherited
    @Published var retryCount = ""
    @Published var retryBaseDelayMs = ""
    @Published var providerMaxRetryDelayMs = ""
    @Published var steeringMode = ""
    @Published var followUpMode = ""
    @Published var transport = ""
    @Published var imageAutoResize = PiOptionalSetting.inherited
    @Published var imageBlocking = PiOptionalSetting.inherited
    @Published var skillCommands = PiOptionalSetting.inherited
    @Published var httpProxy = ""
    @Published var httpIdleTimeoutMs = ""
    @Published var websocketConnectTimeoutMs = ""
    @Published var providerTimeoutMs = ""
    @Published var providerMaxRetries = ""
    @Published var sessionDirectory = ""
    @Published var shellPath = ""
    @Published var shellCommandPrefix = ""
    @Published var npmCommand = ""
    @Published var branchSummaryReserveTokens = ""
    @Published var branchSummarySkipPrompt = PiOptionalSetting.inherited
    @Published var anthropicExtraUsageWarning = PiOptionalSetting.inherited
    @Published var figurePythonPath = ""
    @Published var figureKeepWorkFiles = PiOptionalSetting.inherited
    @Published var overridesTools = false
    @Published var selectedTools = Set<String>()
    @Published var status = ""
    @Published var hasSourceError = false
    @Published var statusIsError = false
    static let builtInTools = ["read", "bash", "edit", "write", "grep", "find", "ls", "powershell"]
    private let builtInTools = PiSettingsEditor.builtInTools
    private var globalURL = PiRuntimeContext.current.settingsURL
    private var projectURL: URL?
    var selectedURL: URL? {
        switch selectedScope {
        case .global: globalURL
        case .project: projectURL
        case .effective: nil
        }
    }

    func configure(globalURL: URL, projectURL: URL?) {
        contextID = UUID()
        self.globalURL = globalURL
        self.projectURL = projectURL
        selectedScope = projectURL == nil ? .global : .project
    }

    func load() {
        do {
            switch selectedScope {
            case .global:
                globalDocument = try PiSettingsFile.read(globalURL)
                baseDocument = globalDocument
            case .project:
                guard let projectURL else {
                    selectedScope = .global
                    load()
                    return
                }
                projectDocument = try PiSettingsFile.read(projectURL)
                globalDocument = (try? PiSettingsFile.read(globalURL)) ?? [:]
                baseDocument = projectDocument
            case .effective:
                globalDocument = try PiSettingsFile.read(globalURL)
                projectDocument = try projectURL.map(PiSettingsFile.read) ?? [:]
                baseDocument = PiSettingsFile.merge(globalDocument, projectDocument)
            }
            populateFields(from: baseDocument)
            status = selectedScope == .effective ? "Merged preview — no file is changed" : "Loaded"
            hasSourceError = false
            statusIsError = false
        } catch {
            baseDocument = [:]
            populateFields(from: [:])
            status = error.localizedDescription
            hasSourceError = true
            statusIsError = true
        }
    }

    private func populateFields(from document: [String: Any]) {
        provider = document["defaultProvider"] as? String ?? ""
        model = document["defaultModel"] as? String ?? ""
        thinkingLevel = document["defaultThinkingLevel"] as? String ?? ""
        enabledModels = stringList(document["enabledModels"])
        modelThinkingLevels = stringDictionary(document["modelThinkingLevels"])
        thinkingBudgetMinimal = numberString(PiSettingsFile.value(in: document, path: ["thinkingBudgets", "minimal"]))
        thinkingBudgetLow = numberString(PiSettingsFile.value(in: document, path: ["thinkingBudgets", "low"]))
        thinkingBudgetMedium = numberString(PiSettingsFile.value(in: document, path: ["thinkingBudgets", "medium"]))
        thinkingBudgetHigh = numberString(PiSettingsFile.value(in: document, path: ["thinkingBudgets", "high"]))
        theme = document["theme"] as? String ?? ""
        compaction = optionalMode(PiSettingsFile.value(in: document, path: ["compaction", "enabled"]))
        compactionReserveTokens = numberString(PiSettingsFile.value(in: document, path: ["compaction", "reserveTokens"]))
        compactionKeepRecentTokens = numberString(PiSettingsFile.value(in: document, path: ["compaction", "keepRecentTokens"]))
        retry = optionalMode(PiSettingsFile.value(in: document, path: ["retry", "enabled"]))
        retryCount = numberString(PiSettingsFile.value(in: document, path: ["retry", "maxRetries"]))
        retryBaseDelayMs = numberString(PiSettingsFile.value(in: document, path: ["retry", "baseDelayMs"]))
        providerMaxRetryDelayMs = numberString(PiSettingsFile.value(in: document, path: ["retry", "provider", "maxRetryDelayMs"]))
        steeringMode = document["steeringMode"] as? String ?? ""
        followUpMode = document["followUpMode"] as? String ?? ""
        transport = document["transport"] as? String ?? ""
        imageAutoResize = optionalMode(PiSettingsFile.value(in: document, path: ["images", "autoResize"]))
        imageBlocking = optionalMode(PiSettingsFile.value(in: document, path: ["images", "blockImages"]))
        skillCommands = optionalMode(document["enableSkillCommands"])
        let proxyDocument = selectedScope == .global ? document : globalDocument
        httpProxy = proxyDocument["httpProxy"] as? String ?? ""
        httpIdleTimeoutMs = numberString(document["httpIdleTimeoutMs"])
        websocketConnectTimeoutMs = numberString(document["websocketConnectTimeoutMs"])
        providerTimeoutMs = numberString(PiSettingsFile.value(in: document, path: ["retry", "provider", "timeoutMs"]))
        providerMaxRetries = numberString(PiSettingsFile.value(in: document, path: ["retry", "provider", "maxRetries"]))
        sessionDirectory = document["sessionDir"] as? String ?? ""
        shellPath = document["shellPath"] as? String ?? ""
        shellCommandPrefix = document["shellCommandPrefix"] as? String ?? ""
        npmCommand = stringList(document["npmCommand"])
        branchSummaryReserveTokens = numberString(PiSettingsFile.value(in: document, path: ["branchSummary", "reserveTokens"]))
        branchSummarySkipPrompt = optionalMode(PiSettingsFile.value(in: document, path: ["branchSummary", "skipPrompt"]))
        anthropicExtraUsageWarning = optionalMode(PiSettingsFile.value(in: document, path: ["warnings", "anthropicExtraUsage"]))
        figurePythonPath = figureSettingValue("pythonPath", in: document) as? String ?? ""
        figureKeepWorkFiles = optionalMode(figureSettingValue("keepWorkFiles", in: document))
        if let tools = document["defaultTools"] as? [String] {
            overridesTools = true
            selectedTools = Set(tools)
        } else {
            overridesTools = false
            selectedTools = []
        }
    }

    private func figureSettingValue(_ key: String, in document: [String: Any]) -> Any? {
        guard selectedScope == .effective else {
            return PiSettingsFile.figureValue(in: document, key: key)
        }
        return PiSettingsFile.effectiveFigureValue(
            global: globalDocument,
            project: projectDocument,
            key: key
        )
    }

    func save() -> Bool {
        guard let selectedURL else { return false }
        let integerFields = [
            ("Reserved response tokens", compactionReserveTokens),
            ("Recent tokens to keep", compactionKeepRecentTokens),
            ("Maximum retries", retryCount),
            ("Retry base delay", retryBaseDelayMs),
            ("Maximum retry delay", providerMaxRetryDelayMs),
            ("Minimal thinking budget", thinkingBudgetMinimal),
            ("Low thinking budget", thinkingBudgetLow),
            ("Medium thinking budget", thinkingBudgetMedium),
            ("High thinking budget", thinkingBudgetHigh),
            ("HTTP idle timeout", httpIdleTimeoutMs),
            ("WebSocket connect timeout", websocketConnectTimeoutMs),
            ("Provider timeout", providerTimeoutMs),
            ("Provider maximum retries", providerMaxRetries),
            ("Branch summary reserve tokens", branchSummaryReserveTokens)
        ]
        for (name, value) in integerFields {
            guard PiSettingsFile.isOptionalNonnegativeInteger(value) else {
                status = "\(name) must be a non-negative integer"
                statusIsError = true
                return false
            }
        }

        let currentDocument: [String: Any]
        do {
            currentDocument = try PiSettingsFile.read(selectedURL)
        } catch {
            status = "Reload required before saving · \(error.localizedDescription)"
            hasSourceError = true
            statusIsError = true
            return false
        }

        var document = currentDocument
        PiSettingsFile.setString(provider, key: "defaultProvider", in: &document)
        PiSettingsFile.setString(model, key: "defaultModel", in: &document)
        PiSettingsFile.setString(thinkingLevel, key: "defaultThinkingLevel", in: &document)
        PiSettingsFile.setStringList(enabledModels, key: "enabledModels", in: &document)
        PiSettingsFile.setStringDictionary(modelThinkingLevels, key: "modelThinkingLevels", in: &document)
        PiSettingsFile.setOptionalInt(thinkingBudgetMinimal, path: ["thinkingBudgets", "minimal"], in: &document)
        PiSettingsFile.setOptionalInt(thinkingBudgetLow, path: ["thinkingBudgets", "low"], in: &document)
        PiSettingsFile.setOptionalInt(thinkingBudgetMedium, path: ["thinkingBudgets", "medium"], in: &document)
        PiSettingsFile.setOptionalInt(thinkingBudgetHigh, path: ["thinkingBudgets", "high"], in: &document)
        PiSettingsFile.setString(theme, key: "theme", in: &document)
        PiSettingsFile.setOptionalBool(compaction, path: ["compaction", "enabled"], in: &document)
        PiSettingsFile.setOptionalInt(compactionReserveTokens, path: ["compaction", "reserveTokens"], in: &document)
        PiSettingsFile.setOptionalInt(compactionKeepRecentTokens, path: ["compaction", "keepRecentTokens"], in: &document)
        PiSettingsFile.setOptionalBool(retry, path: ["retry", "enabled"], in: &document)
        PiSettingsFile.setOptionalInt(retryCount, path: ["retry", "maxRetries"], in: &document)
        PiSettingsFile.setOptionalInt(retryBaseDelayMs, path: ["retry", "baseDelayMs"], in: &document)
        PiSettingsFile.setOptionalInt(providerMaxRetryDelayMs, path: ["retry", "provider", "maxRetryDelayMs"], in: &document)
        PiSettingsFile.setString(steeringMode, key: "steeringMode", in: &document)
        PiSettingsFile.setString(followUpMode, key: "followUpMode", in: &document)
        PiSettingsFile.setString(transport, key: "transport", in: &document)
        PiSettingsFile.setOptionalBool(imageAutoResize, path: ["images", "autoResize"], in: &document)
        PiSettingsFile.setOptionalBool(imageBlocking, path: ["images", "blockImages"], in: &document)
        PiSettingsFile.setOptionalBool(skillCommands, path: ["enableSkillCommands"], in: &document)
        if selectedScope == .global {
            PiSettingsFile.setString(httpProxy, key: "httpProxy", in: &document)
        }
        PiSettingsFile.setOptionalInt(httpIdleTimeoutMs, path: ["httpIdleTimeoutMs"], in: &document)
        PiSettingsFile.setOptionalInt(websocketConnectTimeoutMs, path: ["websocketConnectTimeoutMs"], in: &document)
        PiSettingsFile.setOptionalInt(providerTimeoutMs, path: ["retry", "provider", "timeoutMs"], in: &document)
        PiSettingsFile.setOptionalInt(providerMaxRetries, path: ["retry", "provider", "maxRetries"], in: &document)
        PiSettingsFile.setString(sessionDirectory, key: "sessionDir", in: &document)
        PiSettingsFile.setString(shellPath, key: "shellPath", in: &document)
        PiSettingsFile.setString(shellCommandPrefix, key: "shellCommandPrefix", in: &document)
        PiSettingsFile.setStringList(npmCommand, key: "npmCommand", in: &document)
        PiSettingsFile.setOptionalInt(branchSummaryReserveTokens, path: ["branchSummary", "reserveTokens"], in: &document)
        PiSettingsFile.setOptionalBool(branchSummarySkipPrompt, path: ["branchSummary", "skipPrompt"], in: &document)
        PiSettingsFile.setOptionalBool(anthropicExtraUsageWarning, path: ["warnings", "anthropicExtraUsage"], in: &document)
        let normalizedFigurePythonPath = figurePythonPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        PiSettingsFile.setValue(
            normalizedFigurePythonPath.isEmpty ? nil : normalizedFigurePythonPath,
            path: ["figure", "pythonPath"],
            in: &document
        )
        PiSettingsFile.setOptionalBool(
            figureKeepWorkFiles,
            path: ["figure", "keepWorkFiles"],
            in: &document
        )
        PiSettingsFile.setValue(nil, path: ["scientificFigure", "pythonPath"], in: &document)
        PiSettingsFile.setValue(nil, path: ["scientificFigure", "keepWorkFiles"], in: &document)
        if overridesTools { document["defaultTools"] = builtInTools.filter(selectedTools.contains) }
        else { document.removeValue(forKey: "defaultTools") }
        do {
            try PiSettingsFile.write(document, to: selectedURL)
            baseDocument = document
            if selectedScope == .global { globalDocument = document }
            if selectedScope == .project { projectDocument = document }
            status = "Saved · Pi runtime reloading"
            hasSourceError = false
            statusIsError = false
            return true
        } catch {
            status = error.localizedDescription
            statusIsError = true
            return false
        }
    }

    private func optionalMode(_ value: Any?) -> PiOptionalSetting {
        guard let value = value as? Bool else { return .inherited }
        return value ? .enabled : .disabled
    }

    private func stringList(_ value: Any?) -> String {
        (value as? [String] ?? []).joined(separator: "\n")
    }

    private func stringDictionary(_ value: Any?) -> [String: String] {
        guard let object = value as? [String: Any] else { return [:] }
        return object.reduce(into: [:]) { result, entry in
            if let string = entry.value as? String {
                result[entry.key] = string
            }
        }
    }

    private func numberString(_ value: Any?) -> String {
        (value as? NSNumber)?.stringValue ?? ""
    }

}

enum PiSettingsFile {
    static func isOptionalNonnegativeInteger(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        guard let integer = Int(value) else { return false }
        return integer >= 0
    }

    static func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "PersonalPi.Settings", code: 1, userInfo: [NSLocalizedDescriptionKey: "Settings root must be a JSON object: \(PiFormat.path(url.path))"])
        }
        return object
    }

    static func write(_ object: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw NSError(domain: "PersonalPi.Settings", code: 2, userInfo: [NSLocalizedDescriptionKey: "Settings contain a value that cannot be encoded as JSON"])
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    static func merge(_ base: [String: Any], _ override: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in override {
            if let baseObject = result[key] as? [String: Any], let overrideObject = value as? [String: Any] {
                result[key] = merge(baseObject, overrideObject)
            } else {
                result[key] = value
            }
        }
        return result
    }

    static func value(in object: [String: Any], path: [String]) -> Any? {
        guard let first = path.first else { return nil }
        if path.count == 1 { return object[first] }
        guard let nested = object[first] as? [String: Any] else { return nil }
        return value(in: nested, path: Array(path.dropFirst()))
    }

    static func figureValue(in object: [String: Any], key: String) -> Any? {
        value(in: object, path: ["figure", key])
            ?? value(in: object, path: ["scientificFigure", key])
    }

    static func effectiveFigureValue(
        global: [String: Any],
        project: [String: Any],
        key: String
    ) -> Any? {
        figureValue(in: project, key: key) ?? figureValue(in: global, key: key)
    }

    static func setString(_ raw: String, key: String, in object: inout [String: Any]) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { object.removeValue(forKey: key) }
        else { object[key] = value }
    }

    static func setStringList(_ raw: String, key: String, in object: inout [String: Any]) {
        let values = raw.split { $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if values.isEmpty { object.removeValue(forKey: key) }
        else { object[key] = values }
    }

    static func setStringDictionary(
        _ values: [String: String],
        key: String,
        in object: inout [String: Any]
    ) {
        if values.isEmpty { object.removeValue(forKey: key) }
        else { object[key] = values }
    }

    static func setOptionalBool(_ mode: PiOptionalSetting, path: [String], in object: inout [String: Any]) {
        switch mode {
        case .inherited: setValue(nil, path: path, in: &object)
        case .enabled: setValue(true, path: path, in: &object)
        case .disabled: setValue(false, path: path, in: &object)
        }
    }

    static func setOptionalInt(_ raw: String, path: [String], in object: inout [String: Any]) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        setValue(value.isEmpty ? nil : Int(value), path: path, in: &object)
    }

    static func setValue(_ value: Any?, path: [String], in object: inout [String: Any]) {
        guard let first = path.first else { return }
        if path.count == 1 {
            if let value { object[first] = value }
            else { object.removeValue(forKey: first) }
            return
        }
        var nested = object[first] as? [String: Any] ?? [:]
        setValue(value, path: Array(path.dropFirst()), in: &nested)
        if nested.isEmpty { object.removeValue(forKey: first) }
        else { object[first] = nested }
    }
}
