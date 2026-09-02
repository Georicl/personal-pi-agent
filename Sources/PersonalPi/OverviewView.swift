import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var appState: AppState

    private var gitLine: String {
        if appState.workspaceScope == .global {
            return appState.shortenedScopePath
        }
        var parts = [appState.shortenedScopePath]
        if appState.workspace.git.isRepository {
            parts.append(appState.workspace.branchLabel)
            parts.append(appState.workspace.git.isClean ? "clean" : "\(appState.workspace.git.changedFiles) changed")
        } else {
            parts.append("not a git repo")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            if case .unavailable(let message) = appState.connectionState {
                RuntimeNotice(message: message)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(LocalizedStringKey(PiFormat.greeting()))
                    .font(Theme.serif(34))
                    .foregroundStyle(Theme.ink)

                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 10) {
                        MonoLabel(
                            text: appState.workspaceScope == .global ? "Global chat" : "Current project",
                            size: 9.5,
                            color: Theme.accent
                        )
                        Text(gitLine)
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button("New session") {
                            appState.startNewSession()
                        }
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color(red: 223 / 255, green: 227 / 255, blue: 232 / 255), lineWidth: 1)
                        )
                        .buttonStyle(.plain)
                    }

                    SlashCommandInput(
                        placeholder: appState.workspaceScope == .global
                            ? "What should Pi work on?"
                            : "What should Pi work on in \(appState.workspace.name)?",
                        maximumLines: 4,
                        inputBackground: Theme.canvas,
                        sendButtonSize: 28
                    )

                    HStack(spacing: 14) {
                        Text(LocalizedStringKey(appState.sessionModel))
                        HStack(spacing: 3) {
                            Text("Thinking:")
                            Text(LocalizedStringKey(appState.thinkingLevel.capitalized))
                        }
                        Spacer(minLength: 0)
                        Text("↩ to send")
                    }
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.pale)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
            }

            AccountUsageRow(usageStore: appState.usageStore)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    MonoLabel(text: "Recent sessions", size: 9.5)
                    Spacer()
                    Button("View all") {
                        appState.showAllSessions()
                    }
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                }

                if appState.sidebarSessions.isEmpty {
                    Text("No sessions in this scope yet.")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.faint)
                        .padding(.vertical, 12)
                        .overlay(alignment: .top) { Hairline(color: Theme.rule) }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.sidebarSessions.prefix(6))) { session in
                            Button {
                                appState.selectedSection = .sessions
                                appState.sessionProjectFilter = session.cwd
                                appState.switchSession(session)
                            } label: {
                                HStack(spacing: 14) {
                                    Text(session.clockLabel)
                                        .font(Theme.mono(10.5))
                                        .foregroundStyle(Theme.dim)
                                        .frame(width: 70, alignment: .leading)
                                    Text(session.title)
                                        .font(Theme.sans(13))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text(session.projectName)
                                        .font(Theme.mono(10))
                                        .foregroundStyle(session.projectName == appState.workspace.name ? Theme.accent : Theme.muted)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(
                                            session.projectName == appState.workspace.name ? Theme.wash : Theme.userBubble,
                                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        )
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .top) { Hairline(color: Theme.rule) }
                        }
                    }
                    .overlay(alignment: .bottom) { Hairline(color: Theme.rule) }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 30)
        .frame(maxWidth: 980, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RuntimeNotice: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pi runtime is missing")
                .font(Theme.sans(13.5, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.body)
                .textSelection(.enabled)
            Text("This app is a GUI over Pi CLI. Node is present, but the `pi` command is not.")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.faint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warningFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.warningLine, lineWidth: 1)
        )
    }
}

struct AccountUsageRow: View {
    @ObservedObject var usageStore: AccountUsageStore

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(usageStore.accounts) { account in
                if account.id == "openai-codex" {
                    CodexUsageCard(account: account, usageStore: usageStore)
                        .frame(minWidth: 220, maxWidth: .infinity)
                } else {
                    ProviderUsageCard(account: account)
                        .frame(minWidth: 220, maxWidth: .infinity)
                }
            }
            SessionUsageCard(usageStore: usageStore)
                .frame(minWidth: 220, maxWidth: .infinity)
        }
    }
}

struct ProviderUsageCard: View {
    let account: AccountUsage

    private var statusText: String {
        switch account.state {
        case .live: "ready"
        case .configured: "checking"
        case .unavailable: "unavailable"
        }
    }

    private var statusColor: Color {
        switch account.state {
        case .live: Theme.positive
        case .configured: Theme.warning
        case .unavailable: Theme.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(account.name)
                    .font(Theme.sans(12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Text(LocalizedStringKey(statusText))
                    .font(Theme.mono(9.5))
                    .foregroundStyle(statusColor)
            }
            Text(LocalizedStringKey(account.headline))
                .font(Theme.mono(24))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(LocalizedStringKey(account.detail))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.dim)
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }
}

struct CodexUsageCard: View {
    @Environment(\.locale) private var locale
    let account: AccountUsage
    @ObservedObject var usageStore: AccountUsageStore

    private var statusText: String {
        switch account.state {
        case .live: account.windows.isEmpty ? "oauth ready" : "limits live"
        case .configured: "checking"
        case .unavailable: "unavailable"
        }
    }

    private var statusColor: Color {
        switch account.state {
        case .live: Theme.positive
        case .configured: Theme.warning
        case .unavailable: Theme.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(account.name)
                    .font(Theme.sans(12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Text(LocalizedStringKey(statusText))
                    .font(Theme.mono(9.5))
                    .foregroundStyle(statusColor)
                Button {
                    usageStore.refresh()
                } label: {
                    Image(systemName: usageStore.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
                .disabled(usageStore.isRefreshing)
                .help("Refresh account limits")
            }

            VStack(spacing: 8) {
                if account.windows.isEmpty {
                    UsageMeter(label: "limits", progress: nil, tint: Theme.accent)
                } else {
                    ForEach(Array(account.windows.enumerated()), id: \.element.id) { index, window in
                        UsageMeter(
                            label: window.label,
                            progress: window.progress,
                            tint: index == 0 ? Theme.accent : Theme.accent.opacity(0.55)
                        )
                    }
                }
            }

            Group {
                if account.windows.isEmpty {
                    Text(LocalizedStringKey(account.detail))
                } else {
                    localizedResetSummary
                }
            }
            .font(Theme.mono(10))
            .foregroundStyle(Theme.dim)
            .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }

    private var localizedResetSummary: Text {
        account.windows.enumerated().reduce(Text(verbatim: "")) { summary, item in
            let (index, window) = item
            let remaining = Int(max(0, 100 - window.usedPercent).rounded())
            let reset = window.resetsAt.map(localizedResetDate)
                ?? String(localized: "unknown reset", bundle: .main, locale: locale)
            let separator = index == 0 ? Text(verbatim: "") : Text(verbatim: "  |  ")
            return summary
                + separator
                + Text(verbatim: window.label)
                + Text(verbatim: " ")
                + Text("\(remaining)% remaining")
                + Text(verbatim: " · ")
                + Text("resets")
                + Text(verbatim: " ")
                + Text(verbatim: reset)
        }
    }

    private func localizedResetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMM d HH:mm")
        return formatter.string(from: date)
    }
}

struct UsageMeter: View {
    let label: String
    let progress: Double?
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 9) {
            Text(LocalizedStringKey(label))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.muted)
                .frame(width: 42, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(red: 234 / 255, green: 236 / 255, blue: 239 / 255))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, geo.size.width * CGFloat(min(max(progress ?? 0, 0), 1))))
                }
            }
            .frame(height: 4)
            Text(progress.map { PiFormat.percent($0 * 100) } ?? "—")
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

struct SessionUsageCard: View {
    @ObservedObject var usageStore: AccountUsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Current session")
                    .font(Theme.sans(12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }

            VStack(spacing: 6) {
                metric("tokens", PiFormat.tokens(usageStore.sessionUsage.totalTokens), Theme.ink)
                metric("cost", PiFormat.cost(usageStore.sessionUsage.cost), Theme.ink)
                metric(
                    "context",
                    usageStore.sessionUsage.contextPercent.map { PiFormat.percent($0) } ?? "—",
                    Theme.accent
                )
            }
            .font(Theme.mono(11))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(LocalizedStringKey(label)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).foregroundStyle(color)
        }
    }
}
