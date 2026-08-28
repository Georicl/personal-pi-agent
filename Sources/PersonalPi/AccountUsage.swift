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
    var windows: [AccountUsageWindow]

    var tint: Color {
        switch tintName {
        case "orange": .orange
        case "green": .green
        case "blue": .blue
        default: Theme.accent
        }
    }
}

struct AccountUsageWindow: Identifiable, Sendable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetsAt: Date?

    var progress: Double { min(max(usedPercent / 100, 0), 1) }
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

private enum CodexRateLimitCheck: Sendable {
    case live(planType: String?, windows: [AccountUsageWindow])
    case unavailable(String)
}

private final class CodexAppServerResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var responses: [Int: [String: Any]] = [:]

    func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue else { continue }
            responses[id] = object
            signal.signal()
        }
        lock.unlock()
    }

    func waitForResponse(id: Int, timeout: TimeInterval) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let response = responses.removeValue(forKey: id)
            lock.unlock()
            if let response { return response }
            let remaining = max(0, deadline.timeIntervalSinceNow)
            guard signal.wait(timeout: .now() + remaining) == .success else { break }
        }
        lock.lock()
        let response = responses.removeValue(forKey: id)
        lock.unlock()
        return response
    }
}

private enum CodexAppServerUsageAdapter {
    static func readRateLimits() -> CodexRateLimitCheck {
        guard let executable = PiLaunchConfiguration.resolvedCodexExecutable() else {
            return .unavailable("Codex CLI not found")
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        let collector = CodexAppServerResponseCollector()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.environment = PiLaunchConfiguration.processEnvironment()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.consume(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        defer {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            try? input.fileHandleForWriting.close()
        }

        do {
            try process.run()
            try write(
                [
                    "method": "initialize",
                    "id": 1,
                    "params": [
                        "clientInfo": [
                            "name": "personal_pi",
                            "title": "Personal Pi",
                            "version": "0.1.0"
                        ]
                    ]
                ],
                to: input.fileHandleForWriting
            )
        } catch {
            return .unavailable("Unable to start Codex App Server")
        }

        guard let initialization = collector.waitForResponse(id: 1, timeout: 8),
              initialization["error"] == nil else {
            return .unavailable("Codex App Server initialization failed")
        }

        do {
            try write(["method": "initialized"], to: input.fileHandleForWriting)
            try write(["method": "account/rateLimits/read", "id": 2], to: input.fileHandleForWriting)
        } catch {
            return .unavailable("Unable to request Codex limits")
        }

        guard let response = collector.waitForResponse(id: 2, timeout: 10) else {
            return .unavailable("Codex limit request timed out")
        }
        if let error = response["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Codex limit request failed"
            return .unavailable(message)
        }
        guard let result = response["result"] as? [String: Any] else {
            return .unavailable("Codex returned an invalid limit response")
        }

        let bucket = ((result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any])
            ?? result["rateLimits"] as? [String: Any]
        guard let bucket else {
            return .unavailable("Codex did not return a quota window")
        }

        var windows: [AccountUsageWindow] = []
        if let primary = window(bucket["primary"], id: "primary") { windows.append(primary) }
        if let secondary = window(bucket["secondary"], id: "secondary") { windows.append(secondary) }
        guard !windows.isEmpty else {
            return .unavailable("Codex did not return a quota window")
        }
        return .live(planType: bucket["planType"] as? String, windows: windows)
    }

    private static func write(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func window(_ value: Any?, id: String) -> AccountUsageWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = (object["usedPercent"] as? NSNumber)?.doubleValue,
              let duration = (object["windowDurationMins"] as? NSNumber)?.intValue else { return nil }
        let resetTimestamp = (object["resetsAt"] as? NSNumber)?.doubleValue
        return AccountUsageWindow(
            id: id,
            label: durationLabel(duration),
            usedPercent: usedPercent,
            resetsAt: resetTimestamp.map(Date.init(timeIntervalSince1970:))
        )
    }

    private static func durationLabel(_ minutes: Int) -> String {
        if minutes % 10_080 == 0 { return "\(minutes / 10_080)w" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
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
            async let deepSeekCheck = Task.detached(priority: .utility) {
                PiAuthStatusAdapter.check(provider: "deepseek")
            }.value
            async let codexAuthCheck = Task.detached(priority: .utility) {
                PiAuthStatusAdapter.check(provider: "openai-codex")
            }.value
            async let codexLimitCheck = Task.detached(priority: .utility) {
                CodexAppServerUsageAdapter.readRateLimits()
            }.value
            let checks = await (deepSeekCheck, codexAuthCheck, codexLimitCheck)

            accounts = [
                Self.account(template: Self.deepSeekTemplate, check: checks.0),
                Self.codexAccount(authCheck: checks.1, limitCheck: checks.2)
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
        account.windows = []

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

    private static func codexAccount(
        authCheck: PiProviderAuthCheck,
        limitCheck: CodexRateLimitCheck
    ) -> AccountUsage {
        switch limitCheck {
        case .live(let planType, let windows):
            var account = codexTemplate
            account.state = .live
            account.authLabel = planType.map(planTypeLabel) ?? "ChatGPT"
            account.headline = "Live limits"
            account.detail = resetSummary(windows)
            account.windows = windows
            return account
        case .unavailable(let limitReason):
            var account = account(template: codexTemplate, check: authCheck)
            if account.state == .live {
                account.detail = "OAuth ready · limits unavailable: \(limitReason)"
            }
            return account
        }
    }

    private static func resetSummary(_ windows: [AccountUsageWindow]) -> String {
        windows.map { window in
            let remaining = max(0, 100 - window.usedPercent)
            let reset = window.resetsAt.map(resetFormatter.string) ?? "unknown reset"
            return "\(window.label) \(Int(remaining.rounded()))% remaining · resets \(reset)"
        }.joined(separator: "  |  ")
    }

    private static func planTypeLabel(_ planType: String) -> String {
        planType
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
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
        windows: []
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
        windows: []
    )

    private static let checkingAccounts = [deepSeekTemplate, codexTemplate]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()
}
