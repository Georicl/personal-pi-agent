import Foundation
import SwiftUI
import AppKit

private enum PiSettingsScope: String, CaseIterable, Identifiable {
    case global = "Global"
    case project = "Project"
    case effective = "Effective"

    var id: String { rawValue }
}

private enum PiOptionalSetting: String, CaseIterable, Identifiable {
    case inherited
    case enabled
    case disabled

    var id: String { rawValue }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedScope: PiSettingsScope = .global
    @State private var baseDocument: [String: Any] = [:]
    @State private var globalDocument: [String: Any] = [:]
    @State private var projectDocument: [String: Any] = [:]
    @State private var provider = ""
    @State private var model = ""
    @State private var thinkingLevel = ""
    @State private var theme = ""
    @State private var compaction = PiOptionalSetting.inherited
    @State private var retry = PiOptionalSetting.inherited
    @State private var retryCount = ""
    @State private var skillCommands = PiOptionalSetting.inherited
    @State private var overridesTools = false
    @State private var selectedTools = Set<String>()
    @State private var skills = ""
    @State private var prompts = ""
    @State private var extensions = ""
    @State private var status = ""
    @State private var hasLoadError = false

    private let builtInTools = ["read", "bash", "edit", "write", "grep", "find", "ls", "powershell"]

    private var isReadOnly: Bool { selectedScope == .effective }

    private var globalURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".pi/agent/settings.json")
    }

    private var projectURL: URL {
        URL(fileURLWithPath: appState.workspace.path).appendingPathComponent(".pi/settings.json")
    }

    private var selectedURL: URL? {
        switch selectedScope {
        case .global: globalURL
        case .project: appState.workspaceScope == .workspace ? projectURL : nil
        case .effective: nil
        }
    }

    private var scopeChoices: [PiSettingsScope] {
        appState.workspaceScope == .workspace ? PiSettingsScope.allCases : [.global, .effective]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            scopeCard
            modelCard
            behaviorCard
            toolsCard
            resourcesCard
            saveBar
        }
        .padding(28)
        .frame(maxWidth: 1050, alignment: .leading)
        .task { prepareScopeAndLoad() }
        .onChange(of: selectedScope) { _ in load() }
        .onChange(of: appState.activeWorkingDirectory) { _ in
            if appState.workspaceScope == .global && selectedScope == .project {
                selectedScope = .global
            } else {
                load()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pi settings")
                .font(Theme.serif(26, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Edit Pi-native configuration without exposing credentials. Project values override Global values; Effective is the merged, read-only result.")
                .font(Theme.sans(12.5))
                .foregroundStyle(Theme.muted)
        }
    }

    private var scopeCard: some View {
        SettingsCard(title: "Configuration scope", subtitle: scopeSubtitle) {
            VStack(alignment: .leading, spacing: 13) {
                Picker("Scope", selection: $selectedScope) {
                    ForEach(scopeChoices) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                HStack(spacing: 8) {
                    Image(systemName: isReadOnly ? "arrow.triangle.merge" : "doc.text")
                        .foregroundStyle(Theme.accent)
                    Text(pathLabel)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.muted)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Reload") { load() }
                        .buttonStyle(.borderless)
                    if let selectedURL {
                        Button("Show in Finder") { reveal(selectedURL) }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var modelCard: some View {
        SettingsCard(title: "Model & thinking", subtitle: "Defaults used when Pi starts in this scope.") {
            VStack(spacing: 13) {
                SettingsTextRow(title: "Provider", placeholder: inheritedPlaceholder("provider"), text: $provider)
                SettingsTextRow(title: "Model", placeholder: inheritedPlaceholder("model"), text: $model)

                if !isReadOnly && !appState.availableModels.isEmpty {
                    HStack {
                        Text("Available models")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 150, alignment: .leading)
                        Menu("Choose configured model…") {
                            ForEach(appState.availableModels) { option in
                                Button(option.identity) {
                                    provider = option.provider
                                    model = option.modelId
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        Spacer()
                    }
                }

                SettingsPickerRow(title: "Thinking level") {
                    Picker("Thinking level", selection: $thinkingLevel) {
                        Text(inheritLabel).tag("")
                        ForEach(AppState.thinkingLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }

                SettingsTextRow(title: "Pi CLI theme", placeholder: selectedScope == .project ? "Inherit Global theme" : "Pi default (dark)", text: $theme)
            }
            .disabled(isReadOnly)
        }
    }

    private var behaviorCard: some View {
        SettingsCard(title: "Agent behavior", subtitle: "Compaction and retry are handled by Pi, not the Swift interface.") {
            VStack(spacing: 13) {
                optionalSettingRow(title: "Auto-compaction", selection: $compaction)
                optionalSettingRow(title: "Automatic retry", selection: $retry)
                SettingsTextRow(title: "Maximum retries", placeholder: selectedScope == .project ? "Inherit" : "Pi default (3)", text: $retryCount)
                    .disabled(isReadOnly)
                optionalSettingRow(title: "Skill slash commands", selection: $skillCommands)
            }
        }
    }

    private var toolsCard: some View {
        SettingsCard(title: "Built-in tools", subtitle: "When no override is set, Pi uses its standard defaults or the Global list.") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(selectedScope == .project ? "Override Global tool list" : "Set an explicit tool list", isOn: $overridesTools)
                    .font(Theme.sans(12.5))
                    .disabled(isReadOnly)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 8) {
                    ForEach(builtInTools, id: \.self) { tool in
                        Toggle(tool, isOn: toolBinding(tool))
                            .font(Theme.mono(10.5))
                            .disabled(isReadOnly || !overridesTools)
                    }
                }
                .opacity(overridesTools ? 1 : 0.45)
            }
        }
    }

    private var resourcesCard: some View {
        SettingsCard(title: "Additional resources", subtitle: "One path or glob per line. Pi still auto-discovers the standard skills, prompts and extensions folders.") {
            VStack(spacing: 13) {
                resourceRow(title: "Skills", text: $skills, example: "skills/team/**")
                resourceRow(title: "Prompts", text: $prompts, example: "prompts/research/*.md")
                resourceRow(title: "Extensions", text: $extensions, example: "extensions/*.ts")
            }
            .disabled(isReadOnly)
        }
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            if !status.isEmpty {
                Text(status)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(hasLoadError ? Theme.danger : Theme.muted)
                    .lineLimit(2)
            }
            Spacer()
            if !isReadOnly {
                Button("Save settings") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(hasLoadError)
            }
        }
        .padding(.top, 2)
    }

    private var scopeSubtitle: String {
        switch selectedScope {
        case .global: "Applies to every Pi session unless a project overrides it."
        case .project: "Applies only while \(appState.workspace.name) is the active project."
        case .effective:
            appState.workspaceScope == .workspace
                ? "Global configuration merged with the active project's overrides."
                : "The effective Global configuration used by Global Chat."
        }
    }

    private var pathLabel: String {
        if selectedScope == .effective {
            return appState.workspaceScope == .workspace ? "Global + \(PiFormat.path(projectURL.path))" : "Global configuration"
        }
        guard let selectedURL else { return "No project selected" }
        return PiFormat.path(selectedURL.path)
    }

    private var inheritLabel: String {
        selectedScope == .project ? "Inherit Global" : "Pi default"
    }

    @ViewBuilder
    private func optionalSettingRow(title: String, selection: Binding<PiOptionalSetting>) -> some View {
        SettingsPickerRow(title: title) {
            Picker(title, selection: selection) {
                Text(inheritLabel).tag(PiOptionalSetting.inherited)
                Text("Enabled").tag(PiOptionalSetting.enabled)
                Text("Disabled").tag(PiOptionalSetting.disabled)
            }
            .labelsHidden()
            .frame(width: 210)
            .disabled(isReadOnly)
        }
    }

    @ViewBuilder
    private func resourceRow(title: String, text: Binding<String>, example: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 150, alignment: .leading)
                .padding(.top, 7)
            if isReadOnly {
                Text(text.wrappedValue.isEmpty ? "—" : text.wrappedValue)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(text.wrappedValue.isEmpty ? Theme.pale : Theme.muted)
                    .textSelection(.enabled)
                    .padding(9)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
            } else {
                TextEditor(text: text)
                    .font(Theme.mono(10.5))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 58, maxHeight: 82)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        if text.wrappedValue.isEmpty {
                            Text(example)
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.pale)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    private func toolBinding(_ tool: String) -> Binding<Bool> {
        Binding(
            get: { selectedTools.contains(tool) },
            set: { enabled in
                if enabled { selectedTools.insert(tool) }
                else { selectedTools.remove(tool) }
            }
        )
    }

    private func inheritedPlaceholder(_ field: String) -> String {
        guard selectedScope == .project else { return "Pi default" }
        let key = field == "provider" ? "defaultProvider" : "defaultModel"
        if let value = globalDocument[key] as? String, !value.isEmpty {
            return "Inherit \(value)"
        }
        return "Inherit Global"
    }

    private func prepareScopeAndLoad() {
        selectedScope = appState.workspaceScope == .workspace ? .project : .global
        load()
    }

    private func load() {
        do {
            globalDocument = try PiSettingsFile.read(globalURL)
            projectDocument = appState.workspaceScope == .workspace ? try PiSettingsFile.read(projectURL) : [:]
            switch selectedScope {
            case .global: baseDocument = globalDocument
            case .project: baseDocument = projectDocument
            case .effective: baseDocument = PiSettingsFile.merge(globalDocument, projectDocument)
            }
            populateFields(from: baseDocument)
            status = selectedScope == .effective ? "Merged preview — no file is changed" : "Loaded"
            hasLoadError = false
        } catch {
            status = error.localizedDescription
            hasLoadError = true
        }
    }

    private func populateFields(from document: [String: Any]) {
        provider = document["defaultProvider"] as? String ?? ""
        model = document["defaultModel"] as? String ?? ""
        thinkingLevel = document["defaultThinkingLevel"] as? String ?? ""
        theme = document["theme"] as? String ?? ""
        compaction = optionalMode(PiSettingsFile.value(in: document, path: ["compaction", "enabled"]))
        retry = optionalMode(PiSettingsFile.value(in: document, path: ["retry", "enabled"]))
        retryCount = (PiSettingsFile.value(in: document, path: ["retry", "maxRetries"]) as? NSNumber)?.stringValue ?? ""
        skillCommands = optionalMode(document["enableSkillCommands"])
        if let tools = document["defaultTools"] as? [String] {
            overridesTools = true
            selectedTools = Set(tools)
        } else {
            overridesTools = false
            selectedTools = []
        }
        skills = stringList(document["skills"])
        prompts = stringList(document["prompts"])
        extensions = stringList(document["extensions"])
    }

    private func save() {
        guard let selectedURL else { return }
        if !retryCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let count = Int(retryCount), (0...20).contains(count) else {
                status = "Maximum retries must be an integer between 0 and 20"
                return
            }
        }

        var document = baseDocument
        PiSettingsFile.setString(provider, key: "defaultProvider", in: &document)
        PiSettingsFile.setString(model, key: "defaultModel", in: &document)
        PiSettingsFile.setString(thinkingLevel, key: "defaultThinkingLevel", in: &document)
        PiSettingsFile.setString(theme, key: "theme", in: &document)
        PiSettingsFile.setOptionalBool(compaction, path: ["compaction", "enabled"], in: &document)
        PiSettingsFile.setOptionalBool(retry, path: ["retry", "enabled"], in: &document)
        PiSettingsFile.setOptionalInt(retryCount, path: ["retry", "maxRetries"], in: &document)
        PiSettingsFile.setOptionalBool(skillCommands, path: ["enableSkillCommands"], in: &document)
        if overridesTools { document["defaultTools"] = builtInTools.filter(selectedTools.contains) }
        else { document.removeValue(forKey: "defaultTools") }
        PiSettingsFile.setStringList(skills, key: "skills", in: &document)
        PiSettingsFile.setStringList(prompts, key: "prompts", in: &document)
        PiSettingsFile.setStringList(extensions, key: "extensions", in: &document)

        do {
            try PiSettingsFile.write(document, to: selectedURL)
            baseDocument = document
            status = "Saved · Pi runtime reloading"
            hasLoadError = false
            appState.applySettingsChange()
        } catch {
            status = error.localizedDescription
        }
    }

    private func optionalMode(_ value: Any?) -> PiOptionalSetting {
        guard let value = value as? Bool else { return .inherited }
        return value ? .enabled : .disabled
    }

    private func stringList(_ value: Any?) -> String {
        (value as? [String] ?? []).joined(separator: "\n")
    }

    private func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.sans(13.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.faint)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

private struct SettingsTextRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 150, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono(10.5))
                .frame(maxWidth: 430)
            Spacer()
        }
    }
}

private struct SettingsPickerRow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 150, alignment: .leading)
            content
            Spacer()
        }
    }
}

private enum PiSettingsFile {
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

    private static func setValue(_ value: Any?, path: [String], in object: inout [String: Any]) {
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
