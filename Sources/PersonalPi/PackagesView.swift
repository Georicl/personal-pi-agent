import AppKit
import Foundation
import SwiftUI

struct PackagesView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = PiPackagesViewModel()
    @State private var resourceSearch = ""
    @State private var resourceFilter: PiResourceType?
    @State private var pendingRemoval: PiConfiguredPackage?
    @State private var pendingInstallSource: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            scopeAndSummary
            if !viewModel.snapshot.errors.isEmpty {
                settingsErrorBanner
            }
            packagesPanel
            resourcesPanel
            pathsPanel
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: 1050, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { configureAndLoad() }
        .onChange(of: appState.activeWorkingDirectory) { _ in configureAndLoad() }
        .alert("Install Pi package?", isPresented: installConfirmationBinding) {
            Button("Cancel", role: .cancel) { pendingInstallSource = nil }
            Button("Install") {
                guard let source = pendingInstallSource else { return }
                pendingInstallSource = nil
                viewModel.install(source: source)
            }
        } message: {
            Text("Pi packages can execute code and provide agent instructions with your local user permissions. Install only sources you trust.")
        }
        .alert("Remove Pi package?", isPresented: removalConfirmationBinding) {
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
            Button("Remove", role: .destructive) {
                guard let package = pendingRemoval else { return }
                pendingRemoval = nil
                viewModel.remove(package)
            }
        } message: {
            Text("Pi will remove \(pendingRemoval?.source ?? "") from this scope and delete its managed installation.")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Packages & Resources")
                    .font(Theme.serif(30))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("packages-heading")
                Text("Install Pi packages and control the extensions, skills, prompt templates and themes they provide.")
                    .font(Theme.sans(12.5))
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
            Button("Browse catalog") {
                NSWorkspace.shared.open(URL(string: "https://pi.dev/packages")!)
            }
            .buttonStyle(.borderless)
            Button {
                viewModel.load()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isBusy)
            .accessibilityIdentifier("refresh-packages-button")
        }
    }

    private var scopeAndSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Picker("Scope", selection: scopeBinding) {
                    Text("Global").tag(PiPackageScope.user)
                    if viewModel.projectAvailable {
                        Text("Project").tag(PiPackageScope.project)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .accessibilityIdentifier("package-scope-picker")

                Text(viewModel.scopePathLabel)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            HStack(spacing: 0) {
                PackageStatCell(label: "Configured packages", value: "\(viewModel.visiblePackages.count)", leadingRule: false)
                PackageStatCell(label: "Extensions", value: "\(viewModel.resourceCount(.extensions))")
                PackageStatCell(label: "Skills", value: "\(viewModel.resourceCount(.skills))")
                PackageStatCell(label: "Prompt Templates", value: "\(viewModel.resourceCount(.prompts))")
                PackageStatCell(label: "Themes", value: "\(viewModel.resourceCount(.themes))")
            }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            HStack(spacing: 8) {
                if viewModel.isBusy { ProgressView().controlSize(.small) }
                Text(LocalizedStringKey(viewModel.status))
                    .font(Theme.mono(10))
                    .foregroundStyle(viewModel.statusIsError ? Theme.danger : Theme.muted)
                    .lineLimit(2)
                Spacer()
            }
        }
    }

    private var settingsErrorBanner: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Settings need attention", systemImage: "exclamationmark.triangle")
                .font(Theme.sans(12.5, weight: .medium))
                .foregroundStyle(Theme.warning)
            ForEach(viewModel.snapshot.errors, id: \.self) { error in
                Text(error)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.warning.opacity(0.35), lineWidth: 1))
    }

    private var packagesPanel: some View {
        PackagePanel(
            title: "Installed packages",
            subtitle: viewModel.scope == .project
                ? "Project packages override matching Global packages. Inherited Global packages are shown for context."
                : "Equivalent to Pi list, install, remove and update --extensions."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    TextField("npm:package, Git URL, or local path", text: $viewModel.installSource)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.mono(10.5))
                        .onSubmit { requestInstall() }
                        .accessibilityIdentifier("package-source-input")
                    Button("Install") { requestInstall() }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.installSource.trimmed.isEmpty || viewModel.isBusy || !viewModel.snapshot.errors.isEmpty)
                        .accessibilityIdentifier("install-package-button")
                    Button("Update all") { viewModel.update(source: nil) }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.snapshot.packages.isEmpty || viewModel.isBusy || !viewModel.snapshot.errors.isEmpty)
                        .help("Updates packages from both Global and Project settings, like pi update --extensions.")
                        .accessibilityIdentifier("update-all-packages-button")
                }

                if viewModel.visiblePackages.isEmpty && !viewModel.isLoading {
                    Text("No packages configured in this scope.")
                        .font(Theme.sans(12.5))
                        .foregroundStyle(Theme.faint)
                        .padding(.vertical, 14)
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.visiblePackages) { package in
                            PackageRow(
                                package: package,
                                resources: viewModel.resources(for: package),
                                inherited: viewModel.isInherited(package),
                                disabled: viewModel.isBusy,
                                onUpdate: { viewModel.update(source: package.source) },
                                onRemove: { pendingRemoval = package }
                            )
                        }
                    }
                    .overlay(alignment: .bottom) { Hairline(color: Theme.rule) }
                }
            }
        }
    }

    private var resourcesPanel: some View {
        PackagePanel(
            title: "Resource configuration",
            subtitle: viewModel.scope == .project
                ? "Project overrides can inherit, enable, or disable each resolved resource."
                : "Enable or disable resources discovered by Pi, like pi config."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Filter resources", text: $resourceSearch)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.sans(11.5))
                        .accessibilityIdentifier("resource-search-input")
                    Picker("Resource type", selection: $resourceFilter) {
                        Text("All resources").tag(Optional<PiResourceType>.none)
                        ForEach(PiResourceType.allCases) { type in
                            Text(LocalizedStringKey(type.title)).tag(Optional(type))
                        }
                    }
                    .frame(width: 190)
                }

                if filteredResources.isEmpty && !viewModel.isLoading {
                    Text("No matching resources found.")
                        .font(Theme.sans(12.5))
                        .foregroundStyle(Theme.faint)
                        .padding(.vertical, 14)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredResources) { resource in
                            PackageResourceRow(
                                resource: resource,
                                writeScope: viewModel.scope,
                                disabled: viewModel.isBusy || viewModel.pathsAreDirty || !viewModel.snapshot.errors.isEmpty,
                                onChange: { state in viewModel.setResource(resource, state: state) }
                            )
                        }
                    }
                    .overlay(alignment: .bottom) { Hairline(color: Theme.rule) }
                }
            }
        }
    }

    private var pathsPanel: some View {
        PackagePanel(
            title: "Additional resource paths",
            subtitle: viewModel.scope == .project
                ? "One path or glob per line, resolved relative to the project's .pi directory."
                : "One path or glob per line, resolved relative to the Global Pi agent directory."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(PiResourceType.allCases) { type in
                    ResourcePathRow(
                        type: type,
                        text: viewModel.pathBinding(type),
                        disabled: viewModel.isBusy || !viewModel.snapshot.errors.isEmpty
                    )
                }
                HStack {
                    Text("Supports Pi glob patterns and + / - / ! resource rules.")
                        .font(Theme.sans(9.5))
                        .foregroundStyle(Theme.faint)
                    Spacer()
                    Button("Reset") { viewModel.resetPathEdits() }
                        .buttonStyle(.borderless)
                        .disabled(!viewModel.pathsAreDirty || viewModel.isBusy)
                    Button("Save paths") { viewModel.savePaths() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.pathsAreDirty || viewModel.isBusy || !viewModel.snapshot.errors.isEmpty)
                        .accessibilityIdentifier("save-resource-paths-button")
                }
            }
        }
    }

    private var filteredResources: [PiPackageResource] {
        let query = resourceSearch.trimmed
        return viewModel.visibleResources.filter { resource in
            let matchesType = resourceFilter == nil || resource.resourceType == resourceFilter
            let matchesQuery = query.isEmpty
                || resource.name.localizedCaseInsensitiveContains(query)
                || resource.source.localizedCaseInsensitiveContains(query)
                || resource.path.localizedCaseInsensitiveContains(query)
            return matchesType && matchesQuery
        }
    }

    private var scopeBinding: Binding<PiPackageScope> {
        Binding(get: { viewModel.scope }, set: { viewModel.selectScope($0) })
    }

    private var installConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingInstallSource != nil },
            set: { if !$0 { pendingInstallSource = nil } }
        )
    }

    private var removalConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )
    }

    private func requestInstall() {
        let source = viewModel.installSource.trimmed
        guard !source.isEmpty else { return }
        pendingInstallSource = source
    }

    private func configureAndLoad() {
        viewModel.configure(
            agentDirectory: URL(fileURLWithPath: appState.piRootDirectory)
                .appendingPathComponent("agent", isDirectory: true),
            workingDirectory: URL(
                fileURLWithPath: appState.activeWorkingDirectory,
                isDirectory: true
            ),
            projectAvailable: appState.workspaceScope == .workspace,
            projectName: appState.workspace.name,
            onResourcesChanged: {
                appState.applySettingsChange()
            }
        )
    }
}

private struct PackagePanel<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let content: Content

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
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

private struct PackageStatCell: View {
    let label: String
    let value: String
    var leadingRule = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .textCase(.uppercase)
                .font(Theme.mono(8.5))
                .tracking(0.8)
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(Theme.mono(16))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if leadingRule { Hairline(axis: .vertical, color: Theme.rule) }
        }
    }
}

private struct PackageRow: View {
    let package: PiConfiguredPackage
    let resources: [PiPackageResource]
    let inherited: Bool
    let disabled: Bool
    let onUpdate: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(package.isInstalled ? Theme.accent : Theme.warning)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(package.source)
                            .font(Theme.mono(11, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                        if inherited { packageBadge("Inherited") }
                        if package.filtered { packageBadge("Filtered") }
                        if !package.isInstalled { packageBadge("Missing") }
                    }
                    if let path = package.installedPath {
                        Text(PiFormat.path(path))
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Button("Update", action: onUpdate)
                    .buttonStyle(.borderless)
                    .disabled(disabled || !package.isInstalled)
                if !inherited {
                    Button("Remove", role: .destructive, action: onRemove)
                        .buttonStyle(.borderless)
                        .disabled(disabled)
                }
                if let path = package.installedPath {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Show package in Finder")
                }
            }

            HStack(spacing: 12) {
                ForEach(PiResourceType.allCases) { type in
                    let count = resources.filter { $0.resourceType == type }.count
                    Label {
                        Text("\(count) ") + Text(LocalizedStringKey(type.title))
                    } icon: {
                        Image(systemName: type.icon)
                    }
                        .font(Theme.mono(9))
                        .foregroundStyle(count > 0 ? Theme.muted : Theme.pale)
                }
            }
            .padding(.leading, 28)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Hairline(color: Theme.rule) }
    }

    private func packageBadge(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(Theme.mono(8, weight: .medium))
            .textCase(.uppercase)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.wash, in: RoundedRectangle(cornerRadius: 3))
    }
}

private struct PackageResourceRow: View {
    let resource: PiPackageResource
    let writeScope: PiPackageScope
    let disabled: Bool
    let onChange: (PiResourceOverrideState) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: resource.resourceType.icon)
                .font(.system(size: 11))
                .foregroundStyle(resource.enabled ? Theme.accent : Theme.pale)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(resource.name)
                        .font(Theme.sans(12.5, weight: .medium))
                        .foregroundStyle(resource.enabled ? Theme.ink : Theme.muted)
                    Text(LocalizedStringKey(resource.resourceType.title))
                        .font(Theme.mono(8.5))
                        .foregroundStyle(Theme.dim)
                    if resource.inherited {
                        Text("Inherited Global")
                            .font(Theme.mono(8))
                            .foregroundStyle(Theme.accent)
                    }
                }
                HStack(spacing: 3) {
                    if resource.origin == .package {
                        Text(resource.source)
                    } else {
                        Text("Local")
                    }
                    Text("· \(PiFormat.path(resource.path))")
                }
                .font(Theme.mono(9))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            }
            Spacer()
            if writeScope == .project {
                Menu {
                    ForEach(PiResourceOverrideState.allCases) { state in
                        Button {
                            onChange(state)
                        } label: {
                            Label(
                                LocalizedStringKey(state.title),
                                systemImage: resource.overrideState == state ? "checkmark" : "circle"
                            )
                        }
                    }
                } label: {
                    Text(LocalizedStringKey(resource.overrideState.title))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 125)
                .disabled(disabled)
            } else {
                Toggle("", isOn: globalToggleBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(disabled)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Hairline(color: Theme.rule) }
    }

    private var globalToggleBinding: Binding<Bool> {
        Binding(
            get: { resource.enabled },
            set: { onChange($0 ? .load : .unload) }
        )
    }
}

private struct ResourcePathRow: View {
    let type: PiResourceType
    @Binding var text: String
    let disabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Label(LocalizedStringKey(type.title), systemImage: type.icon)
                .font(Theme.sans(11.5))
                .foregroundStyle(Theme.secondary)
                .frame(width: 150, alignment: .leading)
                .padding(.top, 7)
            TextEditor(text: $text)
                .font(Theme.mono(10))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 52, maxHeight: 72)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
                .disabled(disabled)
        }
    }
}

@MainActor
final class PiPackagesViewModel: ObservableObject {
    @Published var snapshot = PiPackageSnapshot.empty
    @Published var scope: PiPackageScope = .user
    @Published var installSource = ""
    @Published var status = "Loading Pi packages…"
    @Published var statusIsError = false
    @Published var isLoading = false
    @Published var isBusy = false
    @Published var projectAvailable = false
    @Published var projectName = ""
    @Published var pathTexts: [PiResourceType: String] = [:]
    @Published var pathsAreDirty = false

    private var agentDirectory = URL(fileURLWithPath: "/")
    private var workingDirectory = URL(fileURLWithPath: "/")
    private var contextID = UUID()
    private var hasConfigured = false
    private var onResourcesChanged: () -> Void = {}
    private let loader: (URL, URL, @escaping @Sendable (Result<PiPackageSnapshot, Error>) -> Void) -> Void

    init(loader: @escaping (URL, URL, @escaping @Sendable (Result<PiPackageSnapshot, Error>) -> Void) -> Void = {
        PiPackageBridge.load(agentDirectory: $0, workingDirectory: $1, completion: $2)
    }) {
        self.loader = loader
    }

    var scopePathLabel: String {
        if scope == .project {
            return "\(projectName) · .pi/settings.json"
        }
        return PiFormat.path(agentDirectory.appendingPathComponent("settings.json").path)
    }

    var visibleResources: [PiPackageResource] {
        scope == .project ? snapshot.projectResources : snapshot.globalResources
    }

    var scopePackages: [PiConfiguredPackage] {
        snapshot.packages.filter { $0.scope == scope }
    }

    var visiblePackages: [PiConfiguredPackage] {
        if scope == .user { return scopePackages.sorted { $0.source < $1.source } }
        return snapshot.packages.sorted {
            if $0.scope != $1.scope { return $0.scope == .project }
            return $0.source < $1.source
        }
    }

    func configure(
        agentDirectory: URL,
        workingDirectory: URL,
        projectAvailable: Bool,
        projectName: String,
        onResourcesChanged: @escaping () -> Void
    ) {
        let changed = self.agentDirectory != agentDirectory
            || self.workingDirectory != workingDirectory
            || self.projectAvailable != projectAvailable
        self.agentDirectory = agentDirectory
        self.workingDirectory = workingDirectory
        self.projectAvailable = projectAvailable
        self.projectName = projectName
        self.onResourcesChanged = onResourcesChanged
        if !hasConfigured {
            scope = projectAvailable ? .project : .user
            hasConfigured = true
        } else if !projectAvailable {
            scope = .user
        }
        if changed {
            contextID = UUID()
            isBusy = false
            isLoading = false
            snapshot = .empty
            installSource = ""
            pathsAreDirty = false
            pathTexts = [:]
        }
        load()
    }

    func selectScope(_ newScope: PiPackageScope) {
        guard newScope != .project || projectAvailable else { return }
        scope = newScope
        resetPathEdits()
    }

    func resourceCount(_ type: PiResourceType) -> Int {
        visibleResources.filter { $0.resourceType == type }.count
    }

    func resources(for package: PiConfiguredPackage) -> [PiPackageResource] {
        visibleResources.filter {
            $0.origin == .package
                && $0.source == package.source
                && $0.sourceScope == package.scope
        }
    }

    func isInherited(_ package: PiConfiguredPackage) -> Bool {
        scope == .project && package.scope == .user
    }

    func load() {
        let requestID = contextID
        isLoading = true
        if !isBusy {
            status = "Loading Pi packages…"
            statusIsError = false
        }
        loader(
            agentDirectory,
            workingDirectory
        ) { [weak self] result in
            Task { @MainActor in
                guard let self, self.contextID == requestID else { return }
                self.isLoading = false
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    if !self.pathsAreDirty { self.syncPathTexts() }
                    if snapshot.errors.isEmpty && !self.isBusy {
                        self.status = "Packages and resources loaded"
                        self.statusIsError = false
                    } else if let first = snapshot.errors.first {
                        self.status = first
                        self.statusIsError = true
                    }
                case .failure(let error):
                    self.status = error.localizedDescription
                    self.statusIsError = true
                }
            }
        }
    }

    func install(source: String) {
        beginOperation(
            "Installing package…",
            successMessage: "Package installed · Pi runtime reloading",
            clearInstallSourceOnSuccess: true
        ) { completion in
            PiPackageBridge.install(
                source: source,
                scope: self.scope,
                agentDirectory: self.agentDirectory,
                workingDirectory: self.workingDirectory,
                completion: completion
            )
        }
    }

    func remove(_ package: PiConfiguredPackage) {
        beginOperation(
            "Removing package…",
            successMessage: "Package removed · Pi runtime reloading"
        ) { completion in
            PiPackageBridge.remove(
                source: package.source,
                scope: package.scope,
                agentDirectory: self.agentDirectory,
                workingDirectory: self.workingDirectory,
                completion: completion
            )
        }
    }

    func update(source: String?) {
        beginOperation(
            source == nil ? "Updating packages…" : "Updating package…",
            successMessage: "Packages updated · Pi runtime reloading"
        ) { completion in
            PiPackageBridge.update(
                source: source,
                agentDirectory: self.agentDirectory,
                workingDirectory: self.workingDirectory,
                completion: completion
            )
        }
    }

    func setResource(_ resource: PiPackageResource, state: PiResourceOverrideState) {
        beginOperation(
            "Updating resource configuration…",
            successMessage: "Resource configuration saved · Pi runtime reloading"
        ) { completion in
            PiPackageBridge.setResource(
                resource,
                scope: self.scope,
                state: state,
                agentDirectory: self.agentDirectory,
                workingDirectory: self.workingDirectory,
                completion: completion
            )
        }
    }

    func pathBinding(_ type: PiResourceType) -> Binding<String> {
        Binding(
            get: { self.pathTexts[type] ?? "" },
            set: {
                self.pathTexts[type] = $0
                self.pathsAreDirty = true
            }
        )
    }

    func resetPathEdits() {
        pathsAreDirty = false
        syncPathTexts()
    }

    func savePaths() {
        var configuration = PiResourcePathConfiguration.empty
        for type in PiResourceType.allCases {
            configuration[type] = (pathTexts[type] ?? "")
                .split { $0.isNewline }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        beginOperation(
            "Saving resource paths…",
            successMessage: "Resource paths saved · Pi runtime reloading",
            clearPathDirtyOnSuccess: true
        ) { completion in
            PiPackageBridge.setConfiguredPaths(
                configuration,
                scope: self.scope,
                agentDirectory: self.agentDirectory,
                workingDirectory: self.workingDirectory,
                completion: completion
            )
        }
    }

    private func syncPathTexts() {
        let configuration = scope == .project
            ? snapshot.projectConfiguredPaths
            : snapshot.globalConfiguredPaths
        for type in PiResourceType.allCases {
            pathTexts[type] = configuration[type].joined(separator: "\n")
        }
    }

    func beginOperation(
        _ progress: String,
        successMessage: String,
        clearInstallSourceOnSuccess: Bool = false,
        clearPathDirtyOnSuccess: Bool = false,
        operation: (@escaping @Sendable (Result<Void, Error>) -> Void) -> Void
    ) {
        guard !isBusy else { return }
        let requestID = contextID
        isBusy = true
        status = progress
        statusIsError = false
        operation { [weak self] result in
            Task { @MainActor in
                guard let self, self.contextID == requestID else { return }
                self.isBusy = false
                switch result {
                case .success:
                    if clearInstallSourceOnSuccess { self.installSource = "" }
                    if clearPathDirtyOnSuccess { self.pathsAreDirty = false }
                    self.status = successMessage
                    self.statusIsError = false
                    self.onResourcesChanged()
                    self.load()
                case .failure(let error):
                    self.status = error.localizedDescription
                    self.statusIsError = true
                }
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
