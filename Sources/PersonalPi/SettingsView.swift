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
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    @State private var selectedScope: PiSettingsScope = .global
    @State private var baseDocument: [String: Any] = [:]
    @State private var globalDocument: [String: Any] = [:]
    @State private var projectDocument: [String: Any] = [:]
    @State private var provider = ""
    @State private var model = ""
    @State private var thinkingLevel = ""
    @State private var enabledModels = ""
    @State private var modelThinkingLevels: [String: String] = [:]
    @State private var selectedThinkingModel = ""
    @State private var thinkingBudgetMinimal = ""
    @State private var thinkingBudgetLow = ""
    @State private var thinkingBudgetMedium = ""
    @State private var thinkingBudgetHigh = ""
    @State private var showingAdvancedThinking = false
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
    @State private var status = ""
    @State private var hasSourceError = false
    @State private var statusIsError = false
    @State private var isRefreshingModels = false

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
        .onChange(of: appState.availableModels) { _ in
            ensureThinkingModelSelection()
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
                    defaultProviderRow
                    defaultModelRow

                    SettingsPickerRow(title: "Thinking level") {
                        Picker("Thinking level", selection: $thinkingLevel) {
                            Text(LocalizedStringKey(inheritLabel)).tag("")
                            ForEach(defaultThinkingLevelChoices, id: \.self) { level in
                                Text(LocalizedStringKey(choiceLabel(level))).tag(level)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                        .disabled(isReadOnly)
                    }

                    modelCyclingRow
                    perModelThinkingRow

                    DisclosureGroup("Advanced thinking budgets", isExpanded: $showingAdvancedThinking) {
                        VStack(spacing: 10) {
                            SettingsTextRow(title: "Minimal budget", placeholder: "Pi default", text: $thinkingBudgetMinimal)
                            SettingsTextRow(title: "Low budget", placeholder: "Pi default", text: $thinkingBudgetLow)
                            SettingsTextRow(title: "Medium budget", placeholder: "Pi default", text: $thinkingBudgetMedium)
                            SettingsTextRow(title: "High budget", placeholder: "Pi default", text: $thinkingBudgetHigh)
                        }
                        .padding(.top, 10)
                        .disabled(isReadOnly)
                    }
                    .font(Theme.sans(11.5, weight: .medium))
                    .foregroundStyle(Theme.secondary)

                    SettingsTextRow(title: "Pi CLI theme", placeholder: selectedScope == .project ? "Inherit Global theme" : "Pi default (dark)", text: $theme)
                        .disabled(isReadOnly)
                }

                Hairline()

                providerLoginRow
            }
        }
    }

    private var defaultProviderRow: some View {
        SettingsPickerRow(title: "Provider") {
            Picker("Provider", selection: $provider) {
                Text(LocalizedStringKey(inheritLabel)).tag("")
                ForEach(providerChoices, id: \.self) { providerID in
                    Text(providerID).tag(providerID)
                }
            }
            .labelsHidden()
            .frame(width: 300)
            .disabled(isReadOnly)
            .onChange(of: provider) { newProvider in
                let resolvedProvider = newProvider.isEmpty ? inheritedProvider : newProvider
                let available = appState.availableModels.filter { $0.provider == resolvedProvider }
                if !available.isEmpty && !available.contains(where: { $0.modelId == model }) {
                    model = available.first?.modelId ?? ""
                }
            }
            .accessibilityIdentifier("default-provider-picker")
        }
    }

    private var defaultModelRow: some View {
        SettingsPickerRow(title: "Model") {
            Picker("Model", selection: $model) {
                Text(LocalizedStringKey(inheritLabel)).tag("")
                ForEach(modelChoices, id: \.self) { modelID in
                    Text(modelChoiceLabel(modelID)).tag(modelID)
                }
            }
            .labelsHidden()
            .frame(width: 420)
            .disabled(isReadOnly || effectiveProviderForModelSelection.isEmpty)
            .accessibilityIdentifier("default-model-picker")
        }
    }

    private var modelCyclingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text("Model cycling")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 150, alignment: .leading)
                Menu {
                    ForEach(providerChoices, id: \.self) { providerID in
                        let models = appState.availableModels.filter { $0.provider == providerID }
                        if !models.isEmpty {
                            Section(providerID) {
                                ForEach(models) { option in
                                    Button {
                                        toggleEnabledModel(option.identity)
                                    } label: {
                                        Label(
                                            option.displayName,
                                            systemImage: enabledModelPatterns.contains(option.identity)
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                        )
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Text(enabledModelSummary)
                }
                .menuStyle(.borderlessButton)
                .disabled(isReadOnly || appState.availableModels.isEmpty)
                .accessibilityIdentifier("enabled-models-menu")
                if !enabledModelPatterns.isEmpty && !isReadOnly {
                    Button("Clear") { enabledModels = "" }
                        .buttonStyle(.borderless)
                }
                Spacer()
            }

            DisclosureGroup("Advanced model patterns") {
                TextEditor(text: $enabledModels)
                    .font(Theme.mono(10.5))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 54, maxHeight: 76)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
                    .disabled(isReadOnly)
                    .accessibilityIdentifier("enabled-model-patterns-editor")
                Text("One provider/model ID or Pi glob pattern per line.")
                    .font(Theme.sans(9.5))
                    .foregroundStyle(Theme.faint)
            }
            .font(Theme.sans(10.5, weight: .medium))
            .foregroundStyle(Theme.muted)
        }
    }

    private var perModelThinkingRow: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Per-model thinking")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 150, alignment: .leading)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(thinkingModelChoices, id: \.self) { identity in
                            Button(modelIdentityLabel(identity)) {
                                selectedThinkingModel = identity
                            }
                        }
                    } label: {
                        Text(LocalizedStringKey(selectedThinkingModelLabel))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 270, alignment: .leading)
                    .disabled(isReadOnly || thinkingModelChoices.isEmpty)
                    .accessibilityIdentifier("thinking-model-picker")

                    Picker("Per-model thinking", selection: thinkingOverrideBinding) {
                        Text(LocalizedStringKey(inheritLabel)).tag("")
                        ForEach(selectedModelThinkingChoices, id: \.self) { level in
                            Text(LocalizedStringKey(choiceLabel(level))).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .disabled(isReadOnly || selectedThinkingModel.isEmpty)
                    .accessibilityIdentifier("thinking-model-level-picker")
                }
                Text(modelThinkingSummary)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
        }
    }

    private var providerChoices: [String] {
        var choices = Set(appState.availableModels.map(\.provider))
        if !provider.isEmpty { choices.insert(provider) }
        return choices.sorted()
    }

    private var modelChoices: [String] {
        var choices = Set(appState.availableModels.filter {
            $0.provider == effectiveProviderForModelSelection
        }.map(\.modelId))
        if !model.isEmpty { choices.insert(model) }
        return choices.sorted()
    }

    private var selectedDefaultModel: PiModelOption? {
        appState.availableModels.first {
            $0.provider == effectiveProviderForModelSelection && $0.modelId == effectiveModelForThinking
        }
    }

    private var inheritedProvider: String {
        selectedScope == .project ? globalDocument["defaultProvider"] as? String ?? "" : ""
    }

    private var effectiveProviderForModelSelection: String {
        provider.isEmpty ? inheritedProvider : provider
    }

    private var inheritedModel: String {
        selectedScope == .project ? globalDocument["defaultModel"] as? String ?? "" : ""
    }

    private var effectiveModelForThinking: String {
        model.isEmpty ? inheritedModel : model
    }

    private var defaultThinkingLevelChoices: [String] {
        var choices = selectedDefaultModel?.supportedThinkingLevels ?? AppState.thinkingLevels
        if !thinkingLevel.isEmpty && !choices.contains(thinkingLevel) {
            choices.append(thinkingLevel)
        }
        return choices
    }

    private var enabledModelPatterns: [String] {
        enabledModels.split { $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var enabledModelSummary: LocalizedStringKey {
        if enabledModelPatterns.isEmpty { return LocalizedStringKey(inheritLabel) }
        return "\(enabledModelPatterns.count) models or patterns"
    }

    private var thinkingModelChoices: [String] {
        var choices = Set(appState.availableModels.map(\.identity))
        choices.formUnion(modelThinkingLevels.keys)
        return choices.sorted()
    }

    private var selectedThinkingModelLabel: String {
        selectedThinkingModel.isEmpty
            ? "Choose model…"
            : modelIdentityLabel(selectedThinkingModel)
    }

    private var modelThinkingSummary: LocalizedStringKey {
        if modelThinkingLevels.isEmpty { return "No per-model overrides" }
        return "\(modelThinkingLevels.count) per-model overrides"
    }

    private var selectedModelThinkingChoices: [String] {
        var choices = appState.availableModels.first(where: { $0.identity == selectedThinkingModel })?
            .supportedThinkingLevels ?? AppState.thinkingLevels
        if let current = modelThinkingLevels[selectedThinkingModel], !choices.contains(current) {
            choices.append(current)
        }
        return choices
    }

    private var thinkingOverrideBinding: Binding<String> {
        Binding(
            get: { modelThinkingLevels[selectedThinkingModel] ?? "" },
            set: { value in
                if value.isEmpty { modelThinkingLevels.removeValue(forKey: selectedThinkingModel) }
                else { modelThinkingLevels[selectedThinkingModel] = value }
            }
        )
    }

    private func modelChoiceLabel(_ modelID: String) -> String {
        guard let option = appState.availableModels.first(where: {
            $0.provider == effectiveProviderForModelSelection && $0.modelId == modelID
        }) else { return modelID }
        return option.displayName == modelID ? modelID : "\(option.displayName) · \(modelID)"
    }

    private func modelIdentityLabel(_ identity: String) -> String {
        guard let option = appState.availableModels.first(where: { $0.identity == identity }) else {
            return identity
        }
        return option.displayName == option.identity
            ? option.identity
            : "\(option.displayName) · \(option.identity)"
    }

    private func toggleEnabledModel(_ identity: String) {
        var patterns = enabledModelPatterns
        if let index = patterns.firstIndex(of: identity) {
            patterns.remove(at: index)
        } else {
            patterns.append(identity)
        }
        enabledModels = patterns.joined(separator: "\n")
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
            if isRefreshingModels {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Refresh models") {
                refreshModelCatalog()
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshingModels)
            .accessibilityIdentifier("refresh-model-catalog-button")
            Button("Manage accounts") {
                appState.presentProviderAccounts()
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

    private func toolBinding(_ tool: String) -> Binding<Bool> {
        Binding(
            get: { selectedTools.contains(tool) },
            set: { enabled in
                if enabled { selectedTools.insert(tool) }
                else { selectedTools.remove(tool) }
            }
        )
    }

    private func prepareScopeAndLoad() {
        selectedScope = appState.workspaceScope == .workspace ? .project : .global
        load()
    }

    private func refreshModelCatalog() {
        guard !isRefreshingModels else { return }
        isRefreshingModels = true
        status = "Refreshing model catalog…"
        statusIsError = false
        PiProviderAuthBridge.refreshModelCatalog(
            agentDirectory: agentDirectory,
            workingDirectory: URL(
                fileURLWithPath: appState.activeWorkingDirectory,
                isDirectory: true
            )
        ) { result in
            Task { @MainActor in
                isRefreshingModels = false
                switch result {
                case .success:
                    status = "Model catalog refreshed · Pi runtime reloading"
                    appState.applySettingsChange()
                case .failure(let error):
                    status = error.localizedDescription
                    statusIsError = true
                }
            }
        }
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
        if let tools = document["defaultTools"] as? [String] {
            overridesTools = true
            selectedTools = Set(tools)
        } else {
            overridesTools = false
            selectedTools = []
        }
        ensureThinkingModelSelection()
    }

    private func save() {
        guard let selectedURL else { return }
        let integerFields = [
            ("Reserved response tokens", compactionReserveTokens),
            ("Recent tokens to keep", compactionKeepRecentTokens),
            ("Maximum retries", retryCount),
            ("Retry base delay", retryBaseDelayMs),
            ("Maximum retry delay", providerMaxRetryDelayMs),
            ("Minimal thinking budget", thinkingBudgetMinimal),
            ("Low thinking budget", thinkingBudgetLow),
            ("Medium thinking budget", thinkingBudgetMedium),
            ("High thinking budget", thinkingBudgetHigh)
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

    private func ensureThinkingModelSelection() {
        guard !thinkingModelChoices.contains(selectedThinkingModel) else { return }
        let resolvedProvider = provider.isEmpty ? inheritedProvider : provider
        let resolvedModel = model.isEmpty ? inheritedModel : model
        let defaultIdentity = resolvedProvider.isEmpty || resolvedModel.isEmpty
            ? nil
            : "\(resolvedProvider)/\(resolvedModel)"
        selectedThinkingModel = defaultIdentity.flatMap {
            thinkingModelChoices.contains($0) ? $0 : nil
        } ?? modelThinkingLevels.keys.sorted().first ?? thinkingModelChoices.first ?? ""
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

    static func setStringDictionary(
        _ values: [String: String],
        key: String,
        in object: inout [String: Any]
    ) {
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
