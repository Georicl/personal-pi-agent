import AppKit
import SwiftUI

struct ProviderLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue
    @StateObject private var viewModel: ProviderLoginViewModel
    @State private var searchText = ""
    @State private var showingLogoutConfirmation = false

    init(
        agentDirectory: URL,
        workingDirectory: URL,
        request: PiProviderAccountRequest,
        onAuthenticationChanged: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ProviderLoginViewModel(
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory,
            intent: request.intent,
            providerReference: request.providerReference,
            onAuthenticationChanged: onAuthenticationChanged
        ))
    }

    private var interfaceLocale: Locale {
        (AppLanguage(rawValue: languageRawValue) ?? .system).locale
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            content
            Hairline()
            footer
        }
        .frame(width: 720, height: 680)
        .background(Theme.canvas)
        .environment(\.locale, interfaceLocale)
        .task { viewModel.loadProviders() }
        .onDisappear { viewModel.cancelActiveLogin() }
        .alert("Log out of provider?", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Log out", role: .destructive) {
                viewModel.logoutSelectedProvider()
            }
        } message: {
            Text("Pi will remove the stored credential. Environment variables and external configuration are unchanged.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(viewModel.title))
                    .font(Theme.serif(22, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("provider-login-heading")
                Text(LocalizedStringKey(viewModel.subtitle))
                    .font(Theme.sans(11.5))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button {
                viewModel.cancelActiveLogin()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.sans(11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.muted)
            .accessibilityLabel("Cancel")
        }
        .padding(24)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .selecting:
            providerSelection
        case .authenticating:
            authenticationProgress
        case .working:
            accountOperationProgress
        case .complete:
            completionView
        }
    }

    private var providerSelection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.faint)
                TextField("Search providers", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(12.5))
                    .accessibilityIdentifier("provider-search-field")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.faint)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: 1))

            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading providers from Pi…")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredProviders.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(Theme.sans(22))
                        .foregroundStyle(Theme.pale)
                    Text(LocalizedStringKey(emptyProviderMessage))
                        .font(Theme.sans(12.5))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: true) {
                    LazyVStack(spacing: 7) {
                        ForEach(filteredProviders) { provider in
                            ProviderLoginRow(
                                provider: provider,
                                selected: provider.id == viewModel.selectedProviderID
                            ) {
                                viewModel.select(provider)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            if let provider = viewModel.selectedProvider,
               let method = viewModel.selectedMethod {
                selectedProviderDetail(provider: provider, method: method)
            }

            errorBanner
        }
        .padding(24)
    }

    private var filteredProviders: [PiLoginProvider] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.visibleProviders }
        return viewModel.visibleProviders.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
                || $0.methods.contains(where: { $0.name.localizedCaseInsensitiveContains(query) })
        }
    }

    private var emptyProviderMessage: String {
        if !searchText.isEmpty { return "No matching providers" }
        return viewModel.intent == .logout
            ? "No stored provider credentials"
            : "No login providers available"
    }

    private func selectedProviderDetail(
        provider: PiLoginProvider,
        method: PiProviderLoginMethod
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(Theme.sans(12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(method.loginLabel ?? method.name)
                        .font(Theme.sans(10.5))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if viewModel.intent != .logout && provider.methods.count > 1 {
                    Picker("Login method", selection: $viewModel.selectedAuthType) {
                        ForEach(provider.methods) { option in
                            Text(methodLabel(option)).tag(Optional(option.type))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .accessibilityIdentifier("provider-auth-method-picker")
                } else {
                    Text(methodLabel(method))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.accentInk)
                }
            }

            if viewModel.intent == .logout {
                Label("Pi will remove this provider's stored credential", systemImage: "person.crop.circle.badge.minus")
                    .font(Theme.sans(10.5))
                    .foregroundStyle(Theme.muted)
            } else if !method.interactive {
                Label("This provider is configured outside Pi", systemImage: "info.circle")
                    .font(Theme.sans(10.5))
                    .foregroundStyle(Theme.warning)
            } else if method.type == .oauth {
                Label("The authorization page will open automatically", systemImage: "safari")
                    .font(Theme.sans(10.5))
                    .foregroundStyle(Theme.muted)
            } else {
                Label("Pi will securely request and store the required credential", systemImage: "lock.shield")
                    .font(Theme.sans(10.5))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(13)
        .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 8))
    }

    private var authenticationProgress: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accentFill)
                    Image(systemName: viewModel.selectedMethod?.type == .oauth ? "safari" : "key.fill")
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.selectedProvider?.name ?? "Provider")
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(LocalizedStringKey(viewModel.statusMessage))
                        .font(Theme.sans(11.5))
                        .foregroundStyle(Theme.muted)
                }
            }

            if let instructions = viewModel.instructions, !instructions.isEmpty {
                Text(instructions)
                    .font(Theme.sans(11.5))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let deviceCode = viewModel.deviceCode {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Device code")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.muted)
                    Text(deviceCode)
                        .font(Theme.mono(24, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            }

            if viewModel.authorizationURL != nil {
                Button("Open authorization page again") {
                    viewModel.openAuthorizationPage()
                }
                .buttonStyle(.bordered)
            }

            ForEach(Array(viewModel.infoLinks.enumerated()), id: \.offset) { _, link in
                if let url = URL(string: link.url) {
                    Link(link.label ?? link.url, destination: url)
                        .font(Theme.sans(11))
                }
            }

            if let prompt = viewModel.prompt {
                promptView(prompt)
            } else {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for Pi authentication…")
                        .font(Theme.sans(11.5))
                        .foregroundStyle(Theme.muted)
                }
            }

            errorBanner
            Spacer()
        }
        .padding(28)
    }

    private var accountOperationProgress: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(LocalizedStringKey(viewModel.statusMessage))
                .font(Theme.sans(13, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text(viewModel.selectedProvider?.name ?? "")
                .font(Theme.sans(11.5))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func promptView(_ prompt: PiProviderAuthPrompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt.message)
                .font(Theme.sans(12.5, weight: .medium))
                .foregroundStyle(Theme.ink)

            if prompt.type == "select", let options = prompt.options {
                Picker("Select an option", selection: $viewModel.promptInput) {
                    ForEach(options) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 360)
            } else if prompt.type == "secret" {
                SecureField(prompt.placeholder ?? "API key", text: $viewModel.promptInput)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(11))
                    .accessibilityIdentifier("provider-auth-secret-field")
            } else {
                TextField(prompt.placeholder ?? "Value", text: $viewModel.promptInput)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(11))
                    .accessibilityIdentifier("provider-auth-input-field")
            }

            HStack(spacing: 8) {
                Button("Cancel login") { viewModel.cancelPrompt() }
                Button("Submit") { viewModel.submitPrompt() }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.promptInput.isEmpty)
            }
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
    }

    private var completionView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.green.opacity(0.12))
                Image(systemName: "checkmark")
                    .font(Theme.sans(22, weight: .bold))
                    .foregroundStyle(Theme.positive)
            }
            .frame(width: 58, height: 58)
            Text(LocalizedStringKey(viewModel.completionMessage))
                .font(Theme.serif(23, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text(viewModel.selectedProvider?.name ?? "")
                .font(Theme.sans(12.5))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
            Label {
                Text(LocalizedStringKey(errorMessage))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
                .font(Theme.sans(10.5))
                .foregroundStyle(Theme.danger)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.danger.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(viewModel.footerMessage))
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.faint)
            Spacer()
            switch viewModel.phase {
            case .selecting:
                Button("Cancel") { dismiss() }
                if viewModel.canLogOut {
                    Button("Log out", role: .destructive) {
                        showingLogoutConfirmation = true
                    }
                    .accessibilityIdentifier("logout-provider-button")
                }
                if viewModel.intent != .logout {
                    Button(viewModel.selectedMethod?.type == .oauth ? "Continue to authorization" : "Continue") {
                        viewModel.beginLogin()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedMethod?.interactive != true)
                    .accessibilityIdentifier("begin-provider-login-button")
                }
            case .authenticating:
                Button("Cancel login") {
                    viewModel.cancelActiveLogin()
                }
            case .working:
                EmptyView()
            case .complete:
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
    }

    private func methodLabel(_ method: PiProviderLoginMethod) -> LocalizedStringKey {
        if method.type == .oauth {
            return method.subscription ? "Subscription / OAuth" : "OAuth"
        }
        return "API key"
    }
}

private struct ProviderLoginRow: View {
    let provider: PiLoginProvider
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: provider.configured ? "checkmark.circle.fill" : "circle")
                    .font(Theme.sans(14))
                    .foregroundStyle(provider.configured ? Theme.positive : Theme.pale)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.name)
                        .font(Theme.sans(12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(provider.id)
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.faint)
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(provider.methods) { method in
                        Text(method.type == .oauth ? "OAuth" : "API key")
                            .font(Theme.mono(8.5, weight: .medium))
                            .foregroundStyle(method.type == .oauth ? Theme.accentInk : Theme.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                method.type == .oauth ? Theme.accentFill : Theme.panel,
                                in: Capsule()
                            )
                    }
                }
                if provider.configured {
                    Text(LocalizedStringKey(
                        provider.storedAuthType == nil ? "Configured externally" : "Stored credential"
                    ))
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.positive)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(selected ? Theme.accentFill : Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Theme.accentSoft : Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("provider-row-\(provider.id)")
    }
}

@MainActor
private final class ProviderLoginViewModel: ObservableObject {
    enum Phase {
        case selecting
        case authenticating
        case working
        case complete
    }

    @Published var phase = Phase.selecting
    @Published var providers: [PiLoginProvider] = []
    @Published var selectedProviderID: String?
    @Published var selectedAuthType: PiProviderAuthType?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage = "Starting Pi authentication…"
    @Published var instructions: String?
    @Published var authorizationURL: URL?
    @Published var deviceCode: String?
    @Published var infoLinks: [PiProviderAuthLink] = []
    @Published var prompt: PiProviderAuthPrompt?
    @Published var promptInput = ""
    @Published var completionMessage = "Provider connected"

    private let agentDirectory: URL
    private let workingDirectory: URL
    let intent: PiProviderAccountIntent
    private let providerReference: String?
    private let onAuthenticationChanged: () -> Void
    private var loginProcess: PiProviderAuthLoginProcess?
    private var promptID: String?
    private var didLoad = false
    private var lastOpenedURL: URL?

    init(
        agentDirectory: URL,
        workingDirectory: URL,
        intent: PiProviderAccountIntent,
        providerReference: String?,
        onAuthenticationChanged: @escaping () -> Void
    ) {
        self.agentDirectory = agentDirectory
        self.workingDirectory = workingDirectory
        self.intent = intent
        self.providerReference = providerReference
        self.onAuthenticationChanged = onAuthenticationChanged
    }

    var title: String {
        switch intent {
        case .manage: "Model provider accounts"
        case .login: "Log in to model provider"
        case .logout: "Log out of model provider"
        }
    }

    var subtitle: String {
        intent == .logout
            ? "Only credentials stored by Pi are listed. External environment configuration is unchanged."
            : "Providers and login methods are loaded from the installed Pi runtime, just like /login."
    }

    var footerMessage: String {
        intent == .logout
            ? "Logout is handled by Pi and removes only its stored credential."
            : "Authentication is handled by Pi; credential values are not displayed or retained."
    }

    var visibleProviders: [PiLoginProvider] {
        intent == .logout ? providers.filter { $0.storedAuthType != nil } : providers
    }

    var selectedProvider: PiLoginProvider? {
        providers.first(where: { $0.id == selectedProviderID })
    }

    var selectedMethod: PiProviderLoginMethod? {
        guard let provider = selectedProvider else { return nil }
        return provider.methods.first(where: { $0.type == selectedAuthType })
            ?? provider.preferredMethod
    }

    var canLogOut: Bool {
        selectedProvider?.storedAuthType != nil && intent != .login
    }

    func loadProviders(force: Bool = false) {
        guard force || !didLoad else { return }
        didLoad = true
        isLoading = true
        errorMessage = nil
        PiProviderAuthBridge.listProviders(
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let providers):
                    self.providers = providers
                    let candidates = self.visibleProviders
                    if let reference = self.providerReference?.lowercased(),
                       let match = candidates.first(where: {
                           $0.id.lowercased() == reference || $0.name.lowercased() == reference
                       }) {
                        self.select(match)
                    } else if let reference = self.providerReference {
                        self.selectedProviderID = nil
                        self.selectedAuthType = nil
                        self.errorMessage = "Provider not found: \(reference)"
                    } else if let first = candidates.first {
                        self.select(first)
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func select(_ provider: PiLoginProvider) {
        selectedProviderID = provider.id
        selectedAuthType = intent == .logout
            ? provider.storedAuthType
            : provider.configuredAuthType ?? provider.preferredMethod?.type
        errorMessage = nil
    }

    func beginLogin() {
        guard intent != .logout else { return }
        guard let provider = selectedProvider,
              let method = selectedMethod,
              method.interactive else { return }
        errorMessage = nil
        instructions = nil
        authorizationURL = nil
        deviceCode = nil
        infoLinks = []
        prompt = nil
        promptID = nil
        promptInput = ""
        lastOpenedURL = nil
        statusMessage = method.type == .oauth
            ? "Preparing authorization page…"
            : "Waiting for Pi to request credentials…"

        do {
            let process = try PiProviderAuthBridge.makeLoginProcess(
                agentDirectory: agentDirectory,
                workingDirectory: workingDirectory
            )
            process.onEvent = { [weak self] event in
                Task { @MainActor in
                    self?.handle(event)
                }
            }
            loginProcess = process
            phase = .authenticating
            try process.start(providerID: provider.id, authType: method.type)
        } catch {
            loginProcess = nil
            phase = .selecting
            errorMessage = error.localizedDescription
        }
    }

    func submitPrompt() {
        guard let promptID, !promptInput.isEmpty else { return }
        let value = promptInput
        promptInput = ""
        prompt = nil
        self.promptID = nil
        statusMessage = "Continuing authentication…"
        loginProcess?.respond(promptID: promptID, value: value)
    }

    func cancelPrompt() {
        guard let promptID else { return }
        loginProcess?.cancelPrompt(promptID: promptID)
        prompt = nil
        self.promptID = nil
        promptInput = ""
        statusMessage = "Cancelling authentication…"
    }

    func cancelActiveLogin() {
        loginProcess?.cancel()
        loginProcess = nil
        if phase == .authenticating {
            phase = .selecting
            prompt = nil
            promptID = nil
            promptInput = ""
        }
    }

    func openAuthorizationPage() {
        guard let authorizationURL else { return }
        NSWorkspace.shared.open(authorizationURL)
    }

    private func handle(_ event: PiProviderAuthBridgeEvent) {
        switch event {
        case .prompt(let id, let prompt):
            promptID = id
            self.prompt = prompt
            promptInput = prompt.options?.first?.id ?? ""
            statusMessage = prompt.type == "secret"
                ? "Enter the credential requested by Pi"
                : "Complete the next Pi login step"
        case .notification(let event):
            handleNotification(event)
        case .completed(let success, let error):
            loginProcess = nil
            prompt = nil
            promptID = nil
            promptInput = ""
            if success {
                phase = .complete
                statusMessage = "Authentication complete"
                completionMessage = "Provider connected"
                markSelectedProviderConfigured()
                onAuthenticationChanged()
            } else if error != "Login cancelled" {
                phase = .selecting
                errorMessage = error ?? "Pi authentication failed"
            } else {
                phase = .selecting
            }
        }
    }

    func logoutSelectedProvider() {
        guard let provider = selectedProvider, provider.storedAuthType != nil else { return }
        errorMessage = nil
        statusMessage = "Removing stored provider credential…"
        phase = .working
        PiProviderAuthBridge.logoutProvider(
            agentDirectory: agentDirectory,
            workingDirectory: workingDirectory,
            providerID: provider.id
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.phase = .complete
                    self.completionMessage = "Provider logged out"
                    self.markSelectedProviderLoggedOut()
                    self.onAuthenticationChanged()
                case .failure(let error):
                    self.phase = .selecting
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleNotification(_ event: PiProviderAuthNotification) {
        switch event.type {
        case "auth_url":
            statusMessage = "Waiting for authorization in your browser…"
            instructions = event.instructions
            if let rawURL = event.url, let url = URL(string: rawURL) {
                authorizationURL = url
                openOnce(url)
            }
        case "device_code":
            statusMessage = "Enter the device code on the authorization page"
            deviceCode = event.userCode
            if let rawURL = event.verificationUri, let url = URL(string: rawURL) {
                authorizationURL = url
                openOnce(url)
            }
        case "info":
            statusMessage = event.message ?? statusMessage
            infoLinks = event.links ?? []
        case "progress":
            statusMessage = event.message ?? statusMessage
        default:
            break
        }
    }

    private func openOnce(_ url: URL) {
        guard lastOpenedURL != url else { return }
        lastOpenedURL = url
        NSWorkspace.shared.open(url)
    }

    private func markSelectedProviderConfigured() {
        guard let selectedProviderID, let selectedAuthType else { return }
        providers = providers.map { provider in
            guard provider.id == selectedProviderID else { return provider }
            return PiLoginProvider(
                id: provider.id,
                name: provider.name,
                configured: true,
                configuredAuthType: selectedAuthType,
                storedAuthType: selectedAuthType,
                methods: provider.methods
            )
        }
    }

    private func markSelectedProviderLoggedOut() {
        guard let selectedProviderID else { return }
        providers = providers.map { provider in
            guard provider.id == selectedProviderID else { return provider }
            return PiLoginProvider(
                id: provider.id,
                name: provider.name,
                configured: false,
                configuredAuthType: nil,
                storedAuthType: nil,
                methods: provider.methods
            )
        }
    }
}
