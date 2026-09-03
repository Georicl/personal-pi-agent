import AppKit
import SwiftUI

struct SessionUtilitySheet: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue
    let request: PiSessionUtilityRequest

    private var interfaceLocale: Locale {
        (AppLanguage(rawValue: languageRawValue) ?? .system).locale
    }

    var body: some View {
        Group {
            switch request.kind {
            case .info:
                SessionInformationContent()
            case .tree:
                SessionTreeContent()
            case .fork:
                SessionForkContent()
            }
        }
        .frame(width: 720, height: 560)
        .background(Theme.canvas)
        .environment(\.locale, interfaceLocale)
    }
}

private struct SessionInformationContent: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader(title: "Session information", subtitle: "Runtime identity, storage and current usage")

            VStack(spacing: 0) {
                informationRow("Name", value: appState.sessionName)
                informationRow("Scope", value: appState.scopeTitle)
                informationRow("Working directory", value: appState.activeWorkingDirectory, path: true, monospaced: true)
                informationRow("Session ID", value: appState.sessionId, monospaced: true, copyable: appState.sessionId != nil)
                informationRow("Session file", value: appState.sessionFile, path: true, monospaced: true, copyable: appState.sessionFile != nil)
                informationRow("Messages", value: "\(appState.sessionMessageCount)")
                informationRow("Tokens", value: PiFormat.tokens(appState.usageStore.sessionUsage.totalTokens))
                informationRow("Cost", value: PiFormat.cost(appState.usageStore.sessionUsage.cost), isLast: true)
            }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))

            HStack(spacing: 10) {
                if let file = appState.sessionFile {
                    Button("Show session file") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)])
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button("Close") { appState.sessionUtilityRequest = nil }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
    }

    @ViewBuilder
    private func informationRow(
        _ label: LocalizedStringKey,
        value: String?,
        path: Bool = false,
        monospaced: Bool = false,
        copyable: Bool = false,
        isLast: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.muted)
                .frame(width: 130, alignment: .leading)
            Group {
                if let value {
                    Text(path ? PiFormat.path(value) : value)
                        .textSelection(.enabled)
                } else {
                    Text("Not persisted yet")
                }
            }
            .font(monospaced ? Theme.mono(10.5) : Theme.sans(12.5))
            .foregroundStyle(Theme.ink)
            .lineLimit(2)
            .truncationMode(.middle)
            Spacer(minLength: 0)
            if copyable {
                Button {
                    guard let value else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
                .help("Copy")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast { Hairline(color: Theme.rule) }
        }
    }
}

private struct SessionTreeContent: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedEntryId: String?
    @State private var summarize = false
    @State private var customInstructions = ""

    private var rows: [FlatSessionTreeRow] {
        FlatSessionTreeRow.flatten(appState.sessionTree)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader(title: "Session tree", subtitle: "Select an earlier node to continue from that branch")

            Group {
                if appState.isSessionUtilityLoading && rows.isEmpty {
                    ProgressView("Loading session tree…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rows.isEmpty {
                    if appState.sessionUtilityError.isEmpty {
                        emptyState("This session has no saved entries yet.")
                    } else {
                        errorState(appState.sessionUtilityError)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                Button {
                                    selectedEntryId = row.node.id
                                } label: {
                                    SessionTreeRow(
                                        row: row,
                                        selected: selectedEntryId == row.node.id,
                                        current: appState.sessionTreeLeafId == row.node.id
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
                }
            }

            Toggle("Summarize the branch being left", isOn: $summarize)
                .font(Theme.sans(12))
                .disabled(selectedEntryId == nil || selectedEntryId == appState.sessionTreeLeafId)

            if summarize {
                TextField("Optional summary instructions", text: $customInstructions)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.sans(12))
            }

            if !appState.sessionUtilityError.isEmpty && !rows.isEmpty {
                Text(appState.sessionUtilityError)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.danger)
            }

            HStack {
                Button("Cancel") { appState.sessionUtilityRequest = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Navigate here") {
                    guard let selectedEntryId else { return }
                    appState.navigateSessionTree(
                        to: selectedEntryId,
                        summarize: summarize,
                        customInstructions: customInstructions
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    selectedEntryId == nil
                        || selectedEntryId == appState.sessionTreeLeafId
                        || appState.isSessionUtilityLoading
                )
            }
        }
        .padding(26)
        .onAppear { selectedEntryId = appState.sessionTreeLeafId }
    }
}

private struct SessionForkContent: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedEntryId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader(title: "Fork session", subtitle: "Start a new session before an earlier user message")

            Group {
                if appState.isSessionUtilityLoading && appState.forkMessages.isEmpty {
                    ProgressView("Loading user messages…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appState.forkMessages.isEmpty {
                    if appState.sessionUtilityError.isEmpty {
                        emptyState("No user message is available to fork from.")
                    } else {
                        errorState(appState.sessionUtilityError)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(appState.forkMessages) { message in
                                Button {
                                    selectedEntryId = message.entryId
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: selectedEntryId == message.entryId ? "circle.inset.filled" : "circle")
                                            .foregroundStyle(selectedEntryId == message.entryId ? Theme.accent : Theme.pale)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(message.text)
                                                .font(Theme.sans(12.5))
                                                .foregroundStyle(Theme.ink)
                                                .lineLimit(3)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(message.entryId)
                                                .font(Theme.mono(9.5))
                                                .foregroundStyle(Theme.dim)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(13)
                                    .background(selectedEntryId == message.entryId ? Theme.wash : Color.clear)
                                    .overlay(alignment: .bottom) { Hairline(color: Theme.rule) }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
                }
            }

            if !appState.sessionUtilityError.isEmpty && !appState.forkMessages.isEmpty {
                Text(appState.sessionUtilityError)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.danger)
            }

            HStack {
                Button("Cancel") { appState.sessionUtilityRequest = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Fork from message") {
                    guard let selectedEntryId else { return }
                    appState.forkCurrentSession(from: selectedEntryId)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedEntryId == nil || appState.isSessionUtilityLoading)
            }
        }
        .padding(26)
    }
}

private struct FlatSessionTreeRow: Identifiable {
    let node: PiSessionTreeNode
    let depth: Int
    var id: String { node.id }

    static func flatten(_ roots: [PiSessionTreeNode]) -> [FlatSessionTreeRow] {
        var result: [FlatSessionTreeRow] = []
        func append(_ nodes: [PiSessionTreeNode], depth: Int) {
            for node in nodes {
                result.append(FlatSessionTreeRow(node: node, depth: depth))
                append(node.children, depth: depth + 1)
            }
        }
        append(roots, depth: 0)
        return result
    }
}

private struct SessionTreeRow: View {
    let row: FlatSessionTreeRow
    let selected: Bool
    let current: Bool

    private var title: String {
        if let label = row.node.label, !label.isEmpty { return label }
        if let role = row.node.role { return role.capitalized }
        return row.node.type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Color.clear.frame(width: CGFloat(row.depth) * 18, height: 1)
            Image(systemName: current ? "arrowtriangle.right.fill" : "circle.fill")
                .font(.system(size: current ? 9 : 5))
                .foregroundStyle(current ? Theme.accent : Theme.pale)
                .frame(width: 12, height: 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(Theme.mono(10, weight: .medium))
                        .foregroundStyle(current ? Theme.accent : Theme.muted)
                    if current {
                        Text("CURRENT")
                            .font(Theme.mono(8.5, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    if let timestamp = row.node.timestamp {
                        Text(PiFormat.relative(timestamp))
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.dim)
                    }
                }
                if !row.node.text.isEmpty {
                    Text(row.node.text)
                        .font(Theme.sans(11.5))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(selected ? Theme.wash : Color.clear)
        .overlay(alignment: .bottom) { Hairline(color: Theme.rule) }
    }
}

private func sheetHeader(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title)
            .font(Theme.serif(26, weight: .medium))
            .foregroundStyle(Theme.ink)
        Text(subtitle)
            .font(Theme.sans(12.5))
            .foregroundStyle(Theme.muted)
    }
}

private func emptyState(_ message: LocalizedStringKey) -> some View {
    Text(message)
        .font(Theme.sans(12.5))
        .foregroundStyle(Theme.faint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
}

private func errorState(_ message: String) -> some View {
    Text(message)
        .font(Theme.sans(12.5))
        .foregroundStyle(Theme.danger)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
}
