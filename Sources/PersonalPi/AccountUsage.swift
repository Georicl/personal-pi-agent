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
        case .live: "Live"
        case .configured: "Configured"
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

@MainActor
final class AccountUsageStore: ObservableObject {
    @Published private(set) var accounts: [AccountUsage] = [
        AccountUsage(
            id: "deepseek",
            name: "DeepSeek API",
            provider: "deepseek",
            icon: "bolt.fill",
            tintName: "orange",
            authLabel: "API key",
            headline: "Checking balance…",
            detail: "Official /user/balance endpoint",
            state: .configured,
            progress: nil,
            secondaryProgress: nil
        ),
        AccountUsage(
            id: "openai-codex",
            name: "GPT / Codex",
            provider: "openai-codex",
            icon: "sparkles",
            tintName: "green",
            authLabel: "OAuth",
            headline: "OAuth configured",
            detail: "Account limits require the Pi usage extension",
            state: .configured,
            progress: nil,
            secondaryProgress: nil
        )
    ]

    @Published private(set) var sessionUsage = SessionUsage()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated = "Not checked"

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            let credentials = await Task.detached { CredentialReader.read() }.value
            var next = makeConfiguredAccounts(credentials: credentials)

            if let deepSeekKey = credentials.deepSeekKey {
                do {
                    let balance = try await DeepSeekUsageClient.fetchBalance(apiKey: deepSeekKey)
                    if let index = next.firstIndex(where: { $0.id == "deepseek" }) {
                        next[index].state = .live
                        next[index].headline = balance.headline
                        next[index].detail = balance.detail
                    }
                } catch {
                    if let index = next.firstIndex(where: { $0.id == "deepseek" }) {
                        next[index].state = .unavailable
                        next[index].headline = "Balance unavailable"
                        next[index].detail = error.localizedDescription
                    }
                }
            }

            if let codexAccessToken = credentials.codexAccessToken {
                do {
                    let usage = try await CodexUsageClient.fetchUsage(accessToken: codexAccessToken)
                    if let index = next.firstIndex(where: { $0.id == "openai-codex" }) {
                        next[index].state = .live
                        next[index].headline = "Daily \(Self.percent(usage.sessionPercent))%  ·  Weekly \(Self.percent(usage.weeklyPercent))%"
                        next[index].detail = Self.codexDetail(usage)
                        next[index].progress = usage.sessionPercent / 100
                        next[index].secondaryProgress = usage.weeklyPercent / 100
                    }
                } catch {
                    if let index = next.firstIndex(where: { $0.id == "openai-codex" }) {
                        next[index].state = .unavailable
                        next[index].headline = "Usage unavailable"
                        next[index].detail = error.localizedDescription
                    }
                }
            }

            accounts = next
            lastUpdated = Self.dateFormatter.string(from: Date())
            isRefreshing = false
        }
    }

    func updateSessionUsage(_ usage: SessionUsage) {
        sessionUsage = usage
    }

    private func makeConfiguredAccounts(credentials: PiCredentials) -> [AccountUsage] {
        var deepSeek = accounts.first(where: { $0.id == "deepseek" })!
        deepSeek.state = credentials.deepSeekKey == nil ? .unavailable : .configured
        deepSeek.headline = credentials.deepSeekKey == nil ? "Not configured" : "Checking balance…"
        deepSeek.detail = credentials.deepSeekKey == nil ? "No DeepSeek key found in Pi auth" : "Official /user/balance endpoint"

        var codex = accounts.first(where: { $0.id == "openai-codex" })!
        codex.state = credentials.hasCodexOAuth ? .configured : .unavailable
        codex.headline = credentials.hasCodexOAuth ? "OAuth configured" : "Not configured"
        codex.detail = credentials.hasCodexOAuth ? "Checking daily / weekly limits…" : "No Codex OAuth found in Pi auth"
        codex.progress = nil
        codex.secondaryProgress = nil

        return [deepSeek, codex]
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private static func codexDetail(_ usage: CodexUsage) -> String {
        let daily = usage.sessionReset.map { "daily resets in \($0)" } ?? "daily reset unknown"
        let weekly = usage.weeklyReset.map { "weekly resets in \($0)" } ?? "weekly reset unknown"
        return "\(daily)  ·  \(weekly)"
    }
}

struct PiCredentials: Sendable {
    var deepSeekKey: String?
    var hasCodexOAuth: Bool
    var codexAccessToken: String?
}

enum CredentialReader {
    static func read() -> PiCredentials {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".pi/agent/auth.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return PiCredentials(deepSeekKey: nil, hasCodexOAuth: false, codexAccessToken: nil)
        }

        let deepSeekKey = resolvedKey(from: object["deepseek"] as? [String: Any])
        let codex = object["openai-codex"] as? [String: Any]
        let hasCodexOAuth = codex?["type"] as? String == "oauth"
            && codex?["access"] as? String != nil
        let codexAccessToken = hasCodexOAuth ? codex?["access"] as? String : nil

        return PiCredentials(deepSeekKey: deepSeekKey, hasCodexOAuth: hasCodexOAuth, codexAccessToken: codexAccessToken)
    }

    private static func resolvedKey(from credential: [String: Any]?) -> String? {
        guard let raw = credential?["key"] as? String, !raw.isEmpty else { return nil }
        if raw.hasPrefix("$") {
            return ProcessInfo.processInfo.environment[String(raw.dropFirst())]
        }
        // Pi supports command-backed credentials too. The GUI does not execute
        // those commands; it reports the provider as configured but unavailable.
        guard !raw.hasPrefix("!") else { return nil }
        return raw
    }
}

struct DeepSeekBalance: Sendable {
    let headline: String
    let detail: String
}

struct CodexUsage: Sendable {
    let sessionPercent: Double
    let weeklyPercent: Double
    let sessionReset: String?
    let weeklyReset: String?
}

enum CodexUsageClient {
    // This is the same private usage endpoint used by the pi-usage extension.
    // It is intentionally isolated here because the endpoint is not part of
    // the public OpenAI API and may change independently of Pi.
    static func fetchUsage(accessToken: String) async throws -> CodexUsage {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UsageError.httpStatus(http.statusCode)
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimit = object["rate_limit"] as? [String: Any],
              let primary = rateLimit["primary_window"] as? [String: Any],
              let secondary = rateLimit["secondary_window"] as? [String: Any] else {
            throw UsageError.unrecognizedUsage
        }

        let sessionPercent = number(from: primary["used_percent"])
        let weeklyPercent = number(from: secondary["used_percent"])
        guard let sessionPercent, let weeklyPercent else {
            throw UsageError.unrecognizedUsage
        }

        return CodexUsage(
            sessionPercent: max(0, min(100, sessionPercent)),
            weeklyPercent: max(0, min(100, weeklyPercent)),
            sessionReset: duration(from: primary["reset_after_seconds"]),
            weeklyReset: duration(from: secondary["reset_after_seconds"])
        )
    }

    private static func number(from value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func duration(from value: Any?) -> String? {
        guard let seconds = number(from: value), seconds >= 0 else { return nil }
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let hours = totalMinutes / 60
        if hours < 24 { return "\(hours)h \(totalMinutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}

enum DeepSeekUsageClient {
    static func fetchBalance(apiKey: String) async throws -> DeepSeekBalance {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UsageError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        guard let first = decoded.balanceInfos.first else {
            return DeepSeekBalance(
                headline: decoded.isAvailable ? "Balance available" : "Insufficient balance",
                detail: "No balance rows returned"
            )
        }
        let symbol: String
        switch first.currency.uppercased() {
        case "CNY", "RMB": symbol = "¥"
        case "USD": symbol = "$"
        default: symbol = ""
        }
        let headline = symbol.isEmpty ? first.totalBalance : "\(symbol)\(first.totalBalance)"
        let availability = decoded.isAvailable ? "key configured · auth.json" : "Insufficient balance"
        return DeepSeekBalance(
            headline: headline,
            detail: "\(first.currency) · \(availability)"
        )
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

private struct BalanceInfo: Decodable {
    let currency: String
    let totalBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
    }
}

enum UsageError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case unrecognizedUsage

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid provider response"
        case .httpStatus(let status): "Provider returned HTTP \(status)"
        case .unrecognizedUsage: "Usage response shape is not recognized"
        }
    }
}
