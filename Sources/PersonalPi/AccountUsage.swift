import Foundation
import SwiftUI

struct SessionUsage: Sendable {
    var inputTokens = 0
    var outputTokens = 0
    var totalTokens = 0
    var cost = 0.0
    var contextPercent: Double?
}

enum AccountUsageState: String, Sendable {
    case live
    case configured
    case unavailable

    var label: String {
        switch self {
        case .live: "Ready"
        case .configured: "Checking"
        case .unavailable: "Unavailable"
        }
    }
}

struct AccountUsage: Identifiable, Sendable {
    let id: String
    let name: String
    let provider: String
    let icon: String
    let tintName: String
    var authLabel: String
    var headline: String
    var detail: String
    var state: AccountUsageState
    var progress: Double?
    var secondaryProgress: Double?

    var tint: Color {
        switch tintName {
        case "orange": .orange
        case "green": .green
        case "blue": .blue
        default: Theme.accent
        }
    }
}

private enum PiProviderAuthCheck: Sendable {
    case ready(authType: String?)
    case notReady(reason: String)
    case unavailable(String)
}

private enum PiAuthStatusAdapter {
    /// Ask Pi for credential metadata only. The command deliberately omits
    /// `--credentials`, so access tokens and API keys never enter Swift.
    static func check(provider: String) -> PiProviderAuthCheck {
        guard let executable = PiLaunchConfiguration.resolvedExecutable() else {
            return .unavailable("Pi CLI not found")
        }

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        let finished = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "auth", "check",
            "--provider", provider,
            "--json",
            "--no-refresh"
        ]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.environment = PiLaunchConfiguration.processEnvironment()
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return .unavailable("Unable to start Pi auth check")
        }

        guard finished.wait(timeout: .now() + 8) == .success else {
            process.terminate()
            return .unavailable("Pi auth check timed out")
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String,
              object["provider"] as? String == provider else {
            return .unavailable("Pi returned an invalid auth status")
        }
        let blockedFragments = ["credential", "token", "secret", "api_key", "apikey", "access", "refresh"]
        if object.keys.contains(where: { key in
            let normalized = key.lowercased()
            return blockedFragments.contains(where: normalized.contains)
        }) {
            return .unavailable("Pi auth status included an unsupported sensitive field")
        }

        switch status {
        case "ready":
            return .ready(authType: object["authType"] as? String)
        case "not_ready":
            return .notReady(reason: object["reason"] as? String ?? "credential_not_ready")
        default:
            return .unavailable("Unknown Pi auth status: \(status)")
        }
    }
}

@MainActor
final class AccountUsageStore: ObservableObject {
    @Published private(set) var accounts = AccountUsageStore.checkingAccounts
    @Published private(set) var sessionUsage = SessionUsage()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated = "Not checked"

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            let checks = await Task.detached(priority: .utility) {
                (
                    PiAuthStatusAdapter.check(provider: "deepseek"),
                    PiAuthStatusAdapter.check(provider: "openai-codex")
                )
            }.value

            accounts = [
                Self.account(template: Self.deepSeekTemplate, check: checks.0),
                Self.account(template: Self.codexTemplate, check: checks.1)
            ]
            lastUpdated = Self.dateFormatter.string(from: Date())
            isRefreshing = false
        }
    }

    func updateSessionUsage(_ usage: SessionUsage) {
        sessionUsage = usage
    }

    private static func account(template: AccountUsage, check: PiProviderAuthCheck) -> AccountUsage {
        var account = template
        account.progress = nil
        account.secondaryProgress = nil

        switch check {
        case .ready(let authType):
            account.state = .live
            if account.id == "openai-codex" {
                account.headline = "OAuth ready"
                account.detail = "Verified by Pi · usage limits not exposed"
            } else {
                account.headline = authTypeLabel(authType, fallback: "Credential ready")
                account.detail = "Verified by Pi · credential remains hidden"
            }
        case .notReady(let reason):
            account.state = .unavailable
            account.headline = "Not configured"
            account.detail = reasonLabel(reason)
        case .unavailable(let message):
            account.state = .unavailable
            account.headline = "Status unavailable"
            account.detail = message
        }
        return account
    }

    private static func authTypeLabel(_ authType: String?, fallback: String) -> String {
        switch authType {
        case "api_key": "API key ready"
        case "oauth": "OAuth ready"
        case "bearer": "Bearer ready"
        default: fallback
        }
    }

    private static func reasonLabel(_ reason: String) -> String {
        switch reason {
        case "credentials_not_configured": "No credential configured in Pi"
        case "provider_not_found": "Provider is not available in this Pi runtime"
        default: reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static let deepSeekTemplate = AccountUsage(
        id: "deepseek",
        name: "DeepSeek API",
        provider: "deepseek",
        icon: "bolt.fill",
        tintName: "orange",
        authLabel: "API key",
        headline: "Checking Pi…",
        detail: "Credential status via Pi auth check",
        state: .configured,
        progress: nil,
        secondaryProgress: nil
    )

    private static let codexTemplate = AccountUsage(
        id: "openai-codex",
        name: "GPT / Codex",
        provider: "openai-codex",
        icon: "sparkles",
        tintName: "green",
        authLabel: "OAuth",
        headline: "Checking Pi…",
        detail: "Credential status via Pi auth check",
        state: .configured,
        progress: nil,
        secondaryProgress: nil
    )

    private static let checkingAccounts = [deepSeekTemplate, codexTemplate]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
