import Foundation
import Testing
@testable import PersonalPi

@Suite("Pi provider authentication")
struct ProviderAuthTests {
    @Test("Provider list decoding preserves Pi auth methods and status")
    func decodesProviderList() throws {
        let data = Data(#"{"type":"providers","providers":[{"id":"openai-codex","name":"OpenAI Codex","configured":true,"configuredAuthType":"oauth","storedAuthType":"oauth","methods":[{"type":"oauth","name":"OpenAI (ChatGPT Plus/Pro)","interactive":true,"subscription":true}]},{"id":"deepseek","name":"DeepSeek","configured":false,"methods":[{"type":"api_key","name":"DeepSeek API key","interactive":true,"subscription":false}]}]}"#.utf8)

        let providers = try PiProviderAuthBridge.decodeProviderList(data)

        #expect(providers.count == 2)
        #expect(providers[0].id == "openai-codex")
        #expect(providers[0].configuredAuthType == .oauth)
        #expect(providers[0].storedAuthType == .oauth)
        #expect(providers[0].methods.first?.subscription == true)
        #expect(providers[1].methods.first?.type == .apiKey)
    }

    @Test("OAuth is preferred when Pi exposes more than one login method")
    func prefersOAuth() {
        let provider = PiLoginProvider(
            id: "mixed-provider",
            name: "Mixed Provider",
            configured: false,
            configuredAuthType: nil,
            storedAuthType: nil,
            methods: [
                PiProviderLoginMethod(
                    type: .apiKey,
                    name: "API key",
                    loginLabel: nil,
                    interactive: true,
                    subscription: false
                ),
                PiProviderLoginMethod(
                    type: .oauth,
                    name: "Account login",
                    loginLabel: "Sign in",
                    interactive: true,
                    subscription: true
                )
            ]
        )

        #expect(provider.preferredMethod?.type == .oauth)
    }

    @Test("Invalid bridge output is rejected")
    func rejectsInvalidProviderList() {
        #expect(throws: PiProviderAuthBridgeError.self) {
            _ = try PiProviderAuthBridge.decodeProviderList(Data("not-json".utf8))
        }
    }

    @Test("Bridge failures preserve Pi's diagnostic message")
    func decodesBridgeFailure() {
        let data = Data(#"{"type":"result","success":false,"error":"Pi SDK unavailable"}"#.utf8)

        #expect(PiProviderAuthBridge.decodeFailureMessage(data) == "Pi SDK unavailable")
    }

    @Test("Successful one-shot bridge results are recognized")
    func decodesSuccessfulBridgeResult() {
        let data = Data(#"{"type":"result","success":true,"providerId":"openai-codex"}"#.utf8)

        #expect(PiProviderAuthBridge.decodeSuccessfulResult(data))
    }

    @Test("OAuth authorization events preserve the URL for automatic opening")
    func decodesAuthorizationURL() throws {
        let data = Data(#"{"type":"notification","event":{"type":"auth_url","url":"https://auth.example.test/start","instructions":"Continue in browser"}}"#.utf8)

        let event = try PiProviderAuthBridge.decodeEvent(data)

        guard case .notification(let notification) = event else {
            Issue.record("Expected a Pi authentication notification")
            return
        }
        #expect(notification.type == "auth_url")
        #expect(notification.url == "https://auth.example.test/start")
    }

    @Test("Secret prompts remain typed as Pi prompts")
    func decodesSecretPrompt() throws {
        let data = Data(#"{"type":"prompt","id":"prompt-1","prompt":{"type":"secret","message":"Enter API key","placeholder":"API key"}}"#.utf8)

        let event = try PiProviderAuthBridge.decodeEvent(data)

        guard case .prompt(let id, let prompt) = event else {
            Issue.record("Expected a Pi authentication prompt")
            return
        }
        #expect(id == "prompt-1")
        #expect(prompt.type == "secret")
    }
}
