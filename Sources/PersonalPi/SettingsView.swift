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
    @Environment(\.locale) private var locale
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    @State private var selectedScope: PiSettingsScope = .global
    @State private var baseDocument: [String: Any] = [:]
    @State private var globalDocument: [String: Any] = [:]
    @State private var projectDocument: [String: Any] = [:]
    @State private var provider = ""
    @State private var model = ""
    @State private var thinkingLevel = ""
    @State private var theme = ""
    @State private var compaction = PiOptionalSetting.inherited
    @State private var compactionReserveTokens = ""
    @State private var compactionKeepRecentTokens = ""
    @State private var retry = PiOptionalSetting.inherited
    @State private var retryCount = ""
    @State private var retryBaseDelayMs = ""
    @State private var providerMaxRetryDelayMs = ""
    @State private var steeringMode = ""
    @State private var followUpMode = ""
    @State private var transport = ""
    @State private var imageAutoResize = PiOptionalSetting.inherited
    @State private var imageBlocking = PiOptionalSetting.inherited
    @State private var skillCommands = PiOptionalSetting.inherited
    @State private var overridesTools = false
    @State private var selectedTools = Set<String>()
    @State private var skills = ""
    @State private var prompts = ""
    @State private var extensions = ""
    @State private var status = ""
    @State private var hasSourceError = false
    @State private var statusIsError = false
    @State private var showingProviderLogin = false

    private let builtInTools = ["read", "bash", "edit", "write", "grep", "find", "ls", "powershell"]

    private var isReadOnly: Bool { selectedScope == .effective }

    private var globalURL: URL {
        URL(fileURLWithPath: appState.piRootDirectory).appendingPathComponent("agent/settings.json")
    }

    private var projectURL: URL {
        URL(fileURLWithPath: appState.workspace.path).appendingPathComponent(".pi/settings.json")
    }

    private var agentDirectory: URL {
        URL(fileURLWithPath: appState.piRootDirectory).appendingPathComponent("agent", isDirectory: true)
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
        .sheet(isPresented: $showingProviderLogin) {
            ProviderLoginView(
                agentDirectory: agentDirectory,
                workingDirectory: URL(
                    fileURLWithPath: appState.activeWorkingDirectory,
                    isDirectory: true
                )
            ) {
                status = "Provider authentication updated · Pi runtime reloading"
                statusIsError = false
                appState.applySettingsChange()
                appState.usageStore.refresh()
            }
                .environment(\.locale, locale)
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
                        Text(LocalizedStringKey(scope.rawValue)).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                SettingsPickerRow(title: "Interface language") {
                    Picker("Interface language", selection: $languageRawValue) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.titleKey).tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .accessibilityIdentifier("interface-language-picker")
                }

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
                Group {
                    SettingsTextRow(title: "Provider", placeholder: inheritedPlaceholder("provider"), text: $provider)
                    SettingsTextRow(title: "Model", placeholder: inheritedPlaceholder("model"), text: $model)

                    if !appState.availableModels.isEmpty {
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
                            Text(LocalizedStringKey(inheritLabel)).tag("")
                            ForEach(AppState.thinkingLevels, id: \.self) { level in
                                Text(LocalizedStringKey(choiceLabel(level))).tag(level)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                    }

                    SettingsTextRow(title: "Pi CLI theme", placeholder: selectedScope == .project ? "Inherit Global theme" : "Pi default (dark)", text: $theme)
                }
                .disabled(isReadOnly)

                Hairline()

                providerLoginRow
            }
        }
    }

    private var providerLoginRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Model provider accounts")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.secondary)
                Text("Choose from the providers and login methods exposed by Pi /login.")
                    .font(Theme.sans(10.5))
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
            Button("Configure provider") {
                showingProviderLogin = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("configure-model-provider-button")
        }
    }

    private var behaviorCard: some View {
        SettingsCard(title: "Agent behavior", subtitle: "Compaction, retry, delivery and image handling are applied by the Pi runtime.") {
            VStack(spacing: 13) {
                optionalSettingRow(title: "Auto-compaction", selection: $compaction)
                SettingsTextRow(title: "Reserved response tokens", placeholder: selectedScope == .project ? "Inherit" : "Pi default (16384)", text: $compactionReserveTokens)
                    .disabled(isReadOnly)
                SettingsTextRow(title: "Recent tokens to keep", placeholder: selectedScope == .project ? "Inherit" : "Pi default (20000)", text: $compactionKeepRecentTokens)
                    .disabled(isReadOnly)
                optionalSettingRow(title: "Automatic retry", selection: $retry)
                SettingsTextRow(title: "Maximum retries", placeholder: selectedScope == .project ? "Inherit" : "Pi default (3)", text: $retryCount)
                    .disabled(isReadOnly)
                SettingsTextRow(title: "Retry base delay (ms)", placeholder: selectedScope == .project ? "Inherit" : "Pi default (2000)", text: $retryBaseDelayMs)
                    .disabled(isReadOnly)
                SettingsTextRow(title: "Maximum retry delay (ms)", placeholder: selectedScope == .project ? "Inherit" : "Pi default (60000)", text: $providerMaxRetryDelayMs)
                    .disabled(isReadOnly)
                choiceRow(title: "Steering delivery", selection: $steeringMode, options: ["one-at-a-time", "all"])
                choiceRow(title: "Follow-up delivery", selection: $followUpMode, options: ["one-at-a-time", "all"])
                choiceRow(title: "Provider transport", selection: $transport, options: ["auto", "sse", "websocket", "websocket-cached"])
                optionalSettingRow(title: "Resize large images", selection: $imageAutoResize)
                optionalSettingRow(title: "Block images to model", selection: $imageBlocking)
                optionalSettingRow(title: "Skill slash commands", selection: $skillCommands)
            }
        }
    }

    private var toolsCard: some View {
        SettingsCard(title: "Built-in tools", subtitle: "When no override is set, Pi uses its standard defaults or the Global list.") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $overridesTools) {
                    Text(LocalizedStringKey(selectedScope == .project ? "Override Global tool list" : "Set an explicit tool list"))
                }
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
                Text(LocalizedStringKey(status))
                    .font(Theme.mono(10.5))
                    .foregroundStyle(statusIsError ? Theme.danger : Theme.muted)
                    .lineLimit(2)
            }
            Spacer()
            if !isReadOnly {
                Button("Save settings") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(hasSourceError)
            }
        }
        .padding(.top, 2)
    }

    private var scopeSubtitle: LocalizedStringKey {
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
                Text(LocalizedStringKey(inheritLabel)).tag(PiOptionalSetting.inherited)
                Text("Enabled").tag(PiOptionalSetting.enabled)
                Text("Disabled").tag(PiOptionalSetting.disabled)
            }
            .labelsHidden()
            .frame(width: 210)
            .disabled(isReadOnly)
        }
    }

    @ViewBuilder
    private func choiceRow(title: String, selection: Binding<String>, options: [String]) -> some View {
        SettingsPickerRow(title: title) {
            Picker(title, selection: selection) {
                Text(LocalizedStringKey(inheritLabel)).tag("")
                ForEach(options, id: \.self) { option in
                    Text(LocalizedStringKey(choiceLabel(option))).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 210)
            .disabled(isReadOnly)
        }
    }

    @ViewBuilder
    private func resourceRow(title: String, text: Binding<String>, example: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(LocalizedStringKey(title))
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
            switch selectedScope {
            case .global:
                globalDocument = try PiSettingsFile.read(globalURL)
                baseDocument = globalDocument
            case .project:
                projectDocument = try PiSettingsFile.read(projectURL)
                globalDocument = (try? PiSettingsFile.read(globalURL)) ?? [:]
                baseDocument = projectDocument
            case .effective:
                globalDocument = try PiSettingsFile.read(globalURL)
                projectDocument = appState.workspaceScope == .workspace ? try PiSettingsFile.read(projectURL) : [:]
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
        let integerFields = [
            ("Reserved response tokens", compactionReserveTokens),
            ("Recent tokens to keep", compactionKeepRecentTokens),
            ("Maximum retries", retryCount),
            ("Retry base delay", retryBaseDelayMs),
            ("Maximum retry delay", providerMaxRetryDelayMs)
        ]
        for (name, value) in integerFields {
            guard PiSettingsFile.isOptionalNonnegativeInteger(value) else {
                status = "\(name) must be a non-negative integer"
                statusIsError = true
                return
            }
        }

        let currentDocument: [String: Any]
        do {
            currentDocument = try PiSettingsFile.read(selectedURL)
        } catch {
            status = "Reload required before saving · \(error.localizedDescription)"
            hasSourceError = true
            statusIsError = true
            return
        }

        var document = currentDocument
        PiSettingsFile.setString(provider, key: "defaultProvider", in: &document)
        PiSettingsFile.setString(model, key: "defaultModel", in: &document)
        PiSettingsFile.setString(thinkingLevel, key: "defaultThinkingLevel", in: &document)
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
        if overridesTools { document["defaultTools"] = builtInTools.filter(selectedTools.contains) }
        else { document.removeValue(forKey: "defaultTools") }
        PiSettingsFile.setStringList(skills, key: "skills", in: &document)
        PiSettingsFile.setStringList(prompts, key: "prompts", in: &document)
        PiSettingsFile.setStringList(extensions, key: "extensions", in: &document)

        do {
            try PiSettingsFile.write(document, to: selectedURL)
            baseDocument = document
            if selectedScope == .global { globalDocument = document }
            if selectedScope == .project { projectDocument = document }
            status = "Saved · Pi runtime reloading"
            hasSourceError = false
            statusIsError = false
            appState.applySettingsChange()
        } catch {
            status = error.localizedDescription
            statusIsError = true
        }
    }

    private func optionalMode(_ value: Any?) -> PiOptionalSetting {
        guard let value = value as? Bool else { return .inherited }
        return value ? .enabled : .disabled
    }

    private func stringList(_ value: Any?) -> String {
        (value as? [String] ?? []).joined(separator: "\n")
    }

    private func numberString(_ value: Any?) -> String {
        (value as? NSNumber)?.stringValue ?? ""
    }

    private func choiceLabel(_ value: String) -> String {
        switch value {
        case "one-at-a-time": "One at a time"
        case "websocket": "WebSocket"
        case "websocket-cached": "WebSocket cached"
        case "sse": "SSE"
        default: value.capitalized
        }
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
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let content: Content

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey, @ViewBuilder content: () -> Content) {
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
            Text(LocalizedStringKey(title))
                .font(Theme.sans(12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 150, alignment: .leading)
            TextField(LocalizedStringKey(placeholder), text: $text)
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
            Text(LocalizedStringKey(title))
                .font(Theme.sans(12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 150, alignment: .leading)
            content
            Spacer()
        }
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

    fileprivate static func setOptionalBool(_ mode: PiOptionalSetting, path: [String], in object: inout [String: Any]) {
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
