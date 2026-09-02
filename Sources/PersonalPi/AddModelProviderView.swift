import SwiftUI

struct AddModelProviderView: View {
    @Environment(\.dismiss) private var dismiss

    let modelsURL: URL
    let onSave: (PiCustomProviderDraft) throws -> Void

    @State private var draft = PiCustomProviderDraft()
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    providerSection
                    credentialSection
                    modelSection
                    optionsSection
                }
                .padding(24)
            }
            Hairline()
            footer
        }
        .frame(width: 680, height: 680)
        .background(Theme.canvas)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Add model provider")
                    .font(Theme.serif(22, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("add-provider-heading")
                Text("Create a Pi-native provider and its first model. You can add more models later by editing models.json.")
                    .font(Theme.sans(11.5))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button {
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

    private var providerSection: some View {
        ProviderFormSection(
            title: "Provider connection",
            subtitle: "Use the endpoint and API protocol documented by your provider."
        ) {
            ProviderFormTextRow(
                title: "Provider ID",
                placeholder: "my-provider",
                text: $draft.providerID,
                accessibilityIdentifier: "provider-id-field"
            )
            ProviderFormTextRow(
                title: "Base URL",
                placeholder: "https://api.example.com/v1",
                text: $draft.baseURL,
                accessibilityIdentifier: "provider-base-url-field"
            )
            ProviderFormRow(title: "API protocol") {
                Picker("API protocol", selection: $draft.api) {
                    ForEach(PiModelAPI.allCases) { api in
                        Text(api.rawValue).tag(api)
                    }
                }
                .labelsHidden()
                .frame(width: 245)
            }
        }
    }

    private var credentialSection: some View {
        ProviderFormSection(
            title: "Authentication",
            subtitle: "Personal Pi writes only a reference or placeholder here, never the API key itself."
        ) {
            ProviderFormRow(title: "Credential source") {
                Picker("Credential source", selection: $draft.credentialSource) {
                    Text("Pi /login").tag(PiProviderCredentialSource.piLogin)
                    Text("Environment variable").tag(PiProviderCredentialSource.environment)
                    Text("Keyless local server").tag(PiProviderCredentialSource.localPlaceholder)
                }
                .labelsHidden()
                .frame(width: 245)
            }

            if draft.credentialSource == .environment {
                ProviderFormTextRow(
                    title: "Environment variable",
                    placeholder: "MY_PROVIDER_API_KEY",
                    text: $draft.environmentVariable,
                    accessibilityIdentifier: "provider-environment-field"
                )
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: credentialIcon)
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 1)
                Text(credentialHint)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var modelSection: some View {
        ProviderFormSection(
            title: "First model",
            subtitle: "Model ID is sent to the API. Display name is optional."
        ) {
            ProviderFormTextRow(
                title: "Model ID",
                placeholder: "model-id",
                text: $draft.modelID,
                accessibilityIdentifier: "provider-model-id-field"
            )
            ProviderFormTextRow(
                title: "Display name",
                placeholder: "Optional",
                text: $draft.modelName,
                accessibilityIdentifier: "provider-model-name-field"
            )
            ProviderFormTextRow(
                title: "Context window",
                placeholder: "Pi default (128000)",
                text: $draft.contextWindow,
                accessibilityIdentifier: "provider-context-window-field"
            )
            ProviderFormTextRow(
                title: "Maximum output tokens",
                placeholder: "Pi default (16384)",
                text: $draft.maxTokens,
                accessibilityIdentifier: "provider-max-tokens-field"
            )
        }
    }

    private var optionsSection: some View {
        ProviderFormSection(
            title: "Capabilities",
            subtitle: "Only enable features supported by this model and endpoint."
        ) {
            ProviderFormToggleRow(title: "Extended thinking", isOn: $draft.reasoning)
            ProviderFormToggleRow(title: "Image input", isOn: $draft.supportsImages)
            ProviderFormToggleRow(title: "Force Bearer authorization header", isOn: $draft.authHeader)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if !errorMessage.isEmpty {
                    Label {
                        Text(LocalizedStringKey(errorMessage))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(Theme.sans(10.5))
                    .foregroundStyle(Theme.danger)
                } else {
                    Text(PiFormat.path(modelsURL.path))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.faint)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Add provider") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("confirm-add-provider-button")
        }
        .padding(18)
    }

    private var credentialIcon: String {
        switch draft.credentialSource {
        case .piLogin: "lock.shield"
        case .environment: "terminal"
        case .localPlaceholder: "desktopcomputer"
        }
    }

    private var credentialHint: LocalizedStringKey {
        switch draft.credentialSource {
        case .piLogin:
            "After adding, use /login in a session. Pi stores the credential; Personal Pi never reads it."
        case .environment:
            "Enter the variable name without its value. models.json will contain only a $VARIABLE reference."
        case .localPlaceholder:
            "For a local server that ignores authentication. Pi will write a non-secret placeholder so the model is available."
        }
    }

    private func save() {
        do {
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProviderFormSection<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let content: Content

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(Theme.sans(10.5))
                    .foregroundStyle(Theme.faint)
            }
            VStack(spacing: 11) {
                content
            }
        }
    }
}

private struct ProviderFormRow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(LocalizedStringKey(title))
                .font(Theme.sans(11.5))
                .foregroundStyle(Theme.secondary)
                .frame(width: 150, alignment: .leading)
            content
            Spacer()
        }
    }
}

private struct ProviderFormTextRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let accessibilityIdentifier: String

    var body: some View {
        ProviderFormRow(title: title) {
            TextField(LocalizedStringKey(placeholder), text: $text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono(10.5))
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}

private struct ProviderFormToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        ProviderFormRow(title: title) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}
