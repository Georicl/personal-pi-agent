import Foundation
import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    @StateObject private var editor = PiSettingsEditor()
    @State private var selectedThinkingModel = ""
    @State private var showingAdvancedThinking = false
    @State private var showingAdvancedRuntime = false
    @State private var isRefreshingModels = false

    private let builtInTools = PiSettingsEditor.builtInTools

    private var isReadOnly: Bool { editor.selectedScope == .effective }

    private var globalURL: URL {
        PiRuntimeContext.current.settingsURL
    }

    private var projectURL: URL {
        URL(fileURLWithPath: appState.workspace.path).appendingPathComponent(".pi/settings.json")
    }

    private var agentDirectory: URL {
        PiRuntimeContext.current.agentDirectory
    }

    private var selectedURL: URL? {
        switch editor.selectedScope {
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
            advancedRuntimeCard
            toolsCard
            saveBar
        }
        .padding(28)
        .frame(maxWidth: 1050, alignment: .leading)
        .task { prepareScopeAndLoad() }
        .onChange(of: editor.selectedScope) { _ in load() }
        .onChange(of: appState.activeWorkingDirectory) { _ in
            if appState.workspaceScope == .global && editor.selectedScope == .project {
                editor.selectedScope = .global
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
                Picker("Scope", selection: $editor.selectedScope) {
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
                        Picker("Thinking level", selection: $editor.thinkingLevel) {
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
                            SettingsTextRow(title: "Minimal budget", placeholder: "Pi default", text: $editor.thinkingBudgetMinimal)
                            SettingsTextRow(title: "Low budget", placeholder: "Pi default", text: $editor.thinkingBudgetLow)
                            SettingsTextRow(title: "Medium budget", placeholder: "Pi default", text: $editor.thinkingBudgetMedium)
                            SettingsTextRow(title: "High budget", placeholder: "Pi default", text: $editor.thinkingBudgetHigh)
                        }
                        .padding(.top, 10)
                        .disabled(isReadOnly)
                    }
                    .font(Theme.sans(11.5, weight: .medium))
                    .foregroundStyle(Theme.secondary)

                    SettingsTextRow(title: "Pi CLI theme", placeholder: editor.selectedScope == .project ? "Inherit Global theme" : "Pi default (dark)", text: $editor.theme)
                        .disabled(isReadOnly)
                }

                Hairline()

                providerLoginRow
            }
        }
    }

    private var defaultProviderRow: some View {
        SettingsPickerRow(title: "Provider") {
            Picker("Provider", selection: $editor.provider) {
                Text(LocalizedStringKey(inheritLabel)).tag("")
                ForEach(providerChoices, id: \.self) { providerID in
                    Text(providerID).tag(providerID)
                }
            }
            .labelsHidden()
            .frame(width: 300)
            .disabled(isReadOnly)
            .onChange(of: editor.provider) { newProvider in
                let resolvedProvider = newProvider.isEmpty ? inheritedProvider : newProvider
                let available = appState.availableModels.filter { $0.provider == resolvedProvider }
                if !available.isEmpty && !available.contains(where: { $0.modelId == editor.model }) {
                    editor.model = available.first?.modelId ?? ""
                }
            }
            .accessibilityIdentifier("default-provider-picker")
        }
    }

    private var defaultModelRow: some View {
        SettingsPickerRow(title: "Model") {
            Picker("Model", selection: $editor.model) {
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
                    Button("Clear") { editor.enabledModels = "" }
                        .buttonStyle(.borderless)
                }
                Spacer()
            }

            DisclosureGroup("Advanced model patterns") {
                TextEditor(text: $editor.enabledModels)
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
        if !editor.provider.isEmpty { choices.insert(editor.provider) }
        return choices.sorted()
    }

    private var modelChoices: [String] {
        var choices = Set(appState.availableModels.filter {
            $0.provider == effectiveProviderForModelSelection
        }.map(\.modelId))
        if !editor.model.isEmpty { choices.insert(editor.model) }
        return choices.sorted()
    }

    private var selectedDefaultModel: PiModelOption? {
        appState.availableModels.first {
            $0.provider == effectiveProviderForModelSelection && $0.modelId == effectiveModelForThinking
        }
    }

    private var inheritedProvider: String {
        editor.selectedScope == .project ? editor.globalDocument["defaultProvider"] as? String ?? "" : ""
    }

    private var effectiveProviderForModelSelection: String {
        editor.provider.isEmpty ? inheritedProvider : editor.provider
    }

    private var inheritedModel: String {
        editor.selectedScope == .project ? editor.globalDocument["defaultModel"] as? String ?? "" : ""
    }

    private var effectiveModelForThinking: String {
        editor.model.isEmpty ? inheritedModel : editor.model
    }

    private var defaultThinkingLevelChoices: [String] {
        var choices = selectedDefaultModel?.supportedThinkingLevels ?? AppState.thinkingLevels
        if !editor.thinkingLevel.isEmpty && !choices.contains(editor.thinkingLevel) {
            choices.append(editor.thinkingLevel)
        }
        return choices
    }

    private var enabledModelPatterns: [String] {
        editor.enabledModels.split { $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var enabledModelSummary: LocalizedStringKey {
        if enabledModelPatterns.isEmpty { return LocalizedStringKey(inheritLabel) }
        return "\(enabledModelPatterns.count) models or patterns"
    }

    private var thinkingModelChoices: [String] {
        var choices = Set(appState.availableModels.map(\.identity))
        choices.formUnion(editor.modelThinkingLevels.keys)
        return choices.sorted()
    }

    private var selectedThinkingModelLabel: String {
        selectedThinkingModel.isEmpty
            ? "Choose model…"
            : modelIdentityLabel(selectedThinkingModel)
    }

    private var modelThinkingSummary: LocalizedStringKey {
        if editor.modelThinkingLevels.isEmpty { return "No per-model overrides" }
        return "\(editor.modelThinkingLevels.count) per-model overrides"
    }

    private var selectedModelThinkingChoices: [String] {
        var choices = appState.availableModels.first(where: { $0.identity == selectedThinkingModel })?
            .supportedThinkingLevels ?? AppState.thinkingLevels
        if let current = editor.modelThinkingLevels[selectedThinkingModel], !choices.contains(current) {
            choices.append(current)
        }
        return choices
    }

    private var thinkingOverrideBinding: Binding<String> {
        Binding(
            get: { editor.modelThinkingLevels[selectedThinkingModel] ?? "" },
            set: { value in
                if value.isEmpty { editor.modelThinkingLevels.removeValue(forKey: selectedThinkingModel) }
                else { editor.modelThinkingLevels[selectedThinkingModel] = value }
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
        editor.enabledModels = patterns.joined(separator: "\n")
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
                optionalSettingRow(title: "Auto-compaction", selection: $editor.compaction)
                SettingsTextRow(title: "Reserved response tokens", placeholder: editor.selectedScope == .project ? "Inherit" : "Pi default (16384)", text: $editor.compactionReserveTokens)
                    .disabled(isReadOnly)
                SettingsTextRow(title: "Recent tokens to keep", placeholder: editor.selectedScope == .project ? "Inherit" : "Pi default (20000)", text: $editor.compactionKeepRecentTokens)
                    .disabled(isReadOnly)
                optionalSettingRow(title: "Automatic retry", selection: $editor.retry)
                SettingsTextRow(title: "Maximum retries", placeholder: editor.selectedScope == .project ? "Inherit" : "Pi default (3)", text: $editor.retryCount)
                    .disabled(isReadOnly)
                SettingsTextRow(title: "Retry base delay (ms)", placeholder: editor.selectedScope == .project ? "Inherit" : "Pi default (2000)", text: $editor.retryBaseDelayMs)
                    .disabled(isReadOnly)
                SettingsTextRow(title: "Maximum retry delay (ms)", placeholder: editor.selectedScope == .project ? "Inherit" : "Pi default (60000)", text: $editor.providerMaxRetryDelayMs)
                    .disabled(isReadOnly)
                choiceRow(title: "Steering delivery", selection: $editor.steeringMode, options: ["one-at-a-time", "all"])
                choiceRow(title: "Follow-up delivery", selection: $editor.followUpMode, options: ["one-at-a-time", "all"])
                choiceRow(title: "Provider transport", selection: $editor.transport, options: ["auto", "sse", "websocket", "websocket-cached"])
                optionalSettingRow(title: "Resize large images", selection: $editor.imageAutoResize)
                optionalSettingRow(title: "Block images to model", selection: $editor.imageBlocking)
                optionalSettingRow(title: "Skill slash commands", selection: $editor.skillCommands)
            }
        }
    }

    private var toolsCard: some View {
        SettingsCard(title: "Built-in tools", subtitle: "When no override is set, Pi uses its standard defaults or the Global list.") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $editor.overridesTools) {
                    Text(LocalizedStringKey(editor.selectedScope == .project ? "Override Global tool list" : "Set an explicit tool list"))
                }
                    .font(Theme.sans(12.5))
                    .disabled(isReadOnly)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 8) {
                    ForEach(builtInTools, id: \.self) { tool in
                        Toggle(tool, isOn: toolBinding(tool))
                            .font(Theme.mono(10.5))
                            .disabled(isReadOnly || !editor.overridesTools)
                    }
                }
                .opacity(editor.overridesTools ? 1 : 0.45)
            }
        }
    }

    private var advancedRuntimeCard: some View {
        SettingsCard(
            title: "Advanced runtime",
            subtitle: "Figures, network, provider, session, shell and branch-summary settings."
        ) {
            DisclosureGroup("Show advanced options", isExpanded: $showingAdvancedRuntime) {
                VStack(alignment: .leading, spacing: 16) {
                    advancedSection("Figures") {
                        SettingsTextRow(
                            title: "Python executable override",
                            placeholder: editor.selectedScope == .project ? "Inherit managed uv environment" : "Managed uv environment",
                            text: $editor.figurePythonPath
                        )
                        .disabled(isReadOnly)
                        optionalSettingRow(
                            title: "Keep figure work files",
                            selection: $editor.figureKeepWorkFiles
                        )
                        Text("By default Personal Pi keeps only PNG, TIFF and PDF outputs. Source code, requests, validation JSON and logs are retained only when explicitly enabled.")
                            .font(Theme.sans(9.5))
                            .foregroundStyle(Theme.faint)
                            .padding(.leading, 166)
                    }

                    advancedSection("Network & provider") {
                        SettingsTextRow(
                            title: "HTTP proxy",
                            placeholder: "Global only · http://127.0.0.1:7890",
                            text: $editor.httpProxy
                        )
                        .disabled(isReadOnly || editor.selectedScope == .project)
                        Text("Pi reads HTTP proxy from Global settings before project configuration is loaded.")
                            .font(Theme.sans(9.5))
                            .foregroundStyle(Theme.faint)
                            .padding(.leading, 166)
                        SettingsTextRow(title: "HTTP idle timeout (ms)", placeholder: inheritLabel, text: $editor.httpIdleTimeoutMs)
                            .disabled(isReadOnly)
                        SettingsTextRow(title: "WebSocket connect timeout (ms)", placeholder: inheritLabel, text: $editor.websocketConnectTimeoutMs)
                            .disabled(isReadOnly)
                        SettingsTextRow(title: "Provider timeout (ms)", placeholder: inheritLabel, text: $editor.providerTimeoutMs)
                            .disabled(isReadOnly)
                        SettingsTextRow(title: "Provider maximum retries", placeholder: inheritLabel, text: $editor.providerMaxRetries)
                            .disabled(isReadOnly)
                    }

                    advancedSection("Session storage") {
                        SettingsTextRow(
                            title: "Session directory",
                            placeholder: editor.selectedScope == .project ? "Inherit" : "~/.pi/agent/sessions",
                            text: $editor.sessionDirectory
                        )
                        .disabled(isReadOnly)
                        Text("Relative paths are resolved from the active Project or Global Chat directory. The session catalog always keeps Pi's default directory visible.")
                            .font(Theme.sans(9.5))
                            .foregroundStyle(Theme.faint)
                            .padding(.leading, 166)
                        if let override = ProcessInfo.processInfo.environment["PI_CODING_AGENT_SESSION_DIR"],
                           !override.isEmpty {
                            Text("PI_CODING_AGENT_SESSION_DIR currently overrides this setting: \(override)")
                                .font(Theme.mono(9.5))
                                .foregroundStyle(Theme.warning)
                                .padding(.leading, 166)
                        }
                    }
                    advancedSection("Shell & package commands") {
                        SettingsTextRow(title: "Shell path", placeholder: editor.selectedScope == .project ? "Inherit" : "Pi default shell", text: $editor.shellPath)
                            .disabled(isReadOnly)
                        SettingsTextRow(title: "Shell command prefix", placeholder: inheritLabel, text: $editor.shellCommandPrefix)
                            .disabled(isReadOnly)
                        SettingsMultilineTextRow(
                            title: "npm command",
                            help: "One executable or argument per line, for example npm on the first line.",
                            text: $editor.npmCommand
                        )
                        .disabled(isReadOnly)
                    }

                    advancedSection("Branch summaries & warnings") {
                        SettingsTextRow(title: "Branch summary reserve tokens", placeholder: inheritLabel, text: $editor.branchSummaryReserveTokens)
                            .disabled(isReadOnly)
                        optionalSettingRow(title: "Skip branch-summary prompt", selection: $editor.branchSummarySkipPrompt)
                        optionalSettingRow(title: "Anthropic extra-usage warning", selection: $editor.anthropicExtraUsageWarning)
                    }
                }
                .padding(.top, 14)
            }
            .font(Theme.sans(11.5, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .accessibilityIdentifier("advanced-runtime-disclosure")
        }
    }

    @ViewBuilder
    private func advancedSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(Theme.mono(9.5, weight: .medium))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.dim)
            content()
        }
        .padding(.top, 2)
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            if !editor.status.isEmpty {
                Text(LocalizedStringKey(editor.status))
                    .font(Theme.mono(10.5))
                    .foregroundStyle(editor.statusIsError ? Theme.danger : Theme.muted)
                    .lineLimit(2)
            }
            Spacer()
            if !isReadOnly {
                Button("Save settings") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(editor.hasSourceError)
            }
        }
        .padding(.top, 2)
    }

    private var scopeSubtitle: LocalizedStringKey {
        switch editor.selectedScope {
        case .global: "Applies to every Pi session unless a project overrides it."
        case .project: "Applies only while \(appState.workspace.name) is the active project."
        case .effective:
            appState.workspaceScope == .workspace
                ? "Global configuration merged with the active project's overrides."
                : "The effective Global configuration used by Global Chat."
        }
    }

    private var pathLabel: String {
        if editor.selectedScope == .effective {
            return appState.workspaceScope == .workspace ? "Global + \(PiFormat.path(projectURL.path))" : "Global configuration"
        }
        guard let selectedURL else { return "No project selected" }
        return PiFormat.path(selectedURL.path)
    }

    private var inheritLabel: String {
        editor.selectedScope == .project ? "Inherit Global" : "Pi default"
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
            get: { editor.selectedTools.contains(tool) },
            set: { enabled in
                if enabled { editor.selectedTools.insert(tool) }
                else { editor.selectedTools.remove(tool) }
            }
        )
    }

    private func prepareScopeAndLoad() {
        isRefreshingModels = false
        editor.configure(globalURL: globalURL, projectURL: appState.workspaceScope == .workspace ? projectURL : nil)
        load()
    }

    private func refreshModelCatalog() {
        guard !isRefreshingModels else { return }
        isRefreshingModels = true
        let contextID = editor.contextID
        editor.status = "Refreshing model catalog…"
        editor.statusIsError = false
        PiProviderAuthBridge.refreshModelCatalog(
            agentDirectory: agentDirectory,
            workingDirectory: URL(
                fileURLWithPath: appState.activeWorkingDirectory,
                isDirectory: true
            )
        ) { result in
            Task { @MainActor in
                guard editor.contextID == contextID else { return }
                isRefreshingModels = false
                switch result {
                case .success:
                    editor.status = "Model catalog refreshed · Pi runtime reloading"
                    appState.applySettingsChange()
                case .failure(let error):
                    editor.status = error.localizedDescription
                    editor.statusIsError = true
                }
            }
        }
    }

    private func load() {
        editor.load()
        ensureThinkingModelSelection()
    }

    private func save() {
        if editor.save() { appState.applySettingsChange() }
    }

    private func ensureThinkingModelSelection() {
        guard !thinkingModelChoices.contains(selectedThinkingModel) else { return }
        let resolvedProvider = editor.provider.isEmpty ? inheritedProvider : editor.provider
        let resolvedModel = editor.model.isEmpty ? inheritedModel : editor.model
        let defaultIdentity = resolvedProvider.isEmpty || resolvedModel.isEmpty
            ? nil
            : "\(resolvedProvider)/\(resolvedModel)"
        selectedThinkingModel = defaultIdentity.flatMap {
            thinkingModelChoices.contains($0) ? $0 : nil
        } ?? editor.modelThinkingLevels.keys.sorted().first ?? thinkingModelChoices.first ?? ""
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

private struct SettingsMultilineTextRow: View {
    let title: String
    let help: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(LocalizedStringKey(title))
                .font(Theme.sans(12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 150, alignment: .leading)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 5) {
                TextEditor(text: $text)
                    .font(Theme.mono(10.5))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 54, maxHeight: 76)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
                Text(help)
                    .font(Theme.sans(9.5))
                    .foregroundStyle(Theme.faint)
            }
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
