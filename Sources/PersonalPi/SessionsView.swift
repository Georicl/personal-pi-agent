import SwiftUI
import AppKit

struct SessionsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("personalPi.showActivityDrawer") private var showActivityDrawer = true

    var body: some View {
        HStack(spacing: 0) {
            SessionListPanel()
                .frame(width: 224)
            Hairline(axis: .vertical)
            SessionConversationPanel(showActivityDrawer: $showActivityDrawer)
            if showActivityDrawer {
                Hairline(axis: .vertical)
                AgentActivityPanel(showActivityDrawer: $showActivityDrawer)
                    .frame(width: 270)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .task {
            appState.refreshSavedSessions()
        }
    }
}

struct SessionListPanel: View {
    @EnvironmentObject private var appState: AppState

    private var filterName: String {
        if let path = appState.sessionProjectFilter {
            let name = URL(fileURLWithPath: path).lastPathComponent
            return name.isEmpty ? "Filtered" : name
        }
        return appState.scopeTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Sessions")
                        .font(Theme.sans(12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(appState.visibleSessions.count)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.dim)
                    Button {
                        appState.refreshSavedSessions()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh sessions")
                }

                HStack(spacing: 5) {
                    FilterChip(title: filterName, selected: true) {}
                    FilterChip(title: "All", selected: false) {
                        appState.sessionProjectFilter = nil
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Hairline() }

            if appState.visibleSessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No saved sessions yet")
                        .font(Theme.sans(12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("Sessions created by Pi will appear here.")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.faint)
                }
                .padding(16)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedSessions) { group in
                            if let title = group.title {
                                Text(title.uppercased())
                                    .font(Theme.mono(9.5))
                                    .tracking(1.2)
                                    .foregroundStyle(Theme.pale)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 10)
                                    .padding(.bottom, 6)
                            }
                            ForEach(group.sessions) { session in
                                SessionListRow(
                                    session: session,
                                    isSelected: session.id == appState.sessionId
                                ) {
                                    appState.switchSession(session)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }

    private var groupedSessions: [SessionDayGroup] {
        var groups: [SessionDayGroup] = []
        var currentKey: String?
        var bucket: [PiSavedSession] = []
        let calendar = Calendar.current

        for session in appState.visibleSessions {
            let day = calendar.startOfDay(for: session.timestamp)
            let key = ISO8601DateFormatter().string(from: day)
            if currentKey != key {
                if let currentKey, !bucket.isEmpty {
                    groups.append(
                        SessionDayGroup(
                            id: currentKey,
                            title: PiFormat.dayHeader(bucket[0].timestamp),
                            sessions: bucket
                        )
                    )
                }
                currentKey = key
                bucket = [session]
            } else {
                bucket.append(session)
            }
        }
        if let currentKey, !bucket.isEmpty {
            groups.append(
                SessionDayGroup(
                    id: currentKey,
                    title: PiFormat.dayHeader(bucket[0].timestamp),
                    sessions: bucket
                )
            )
        }
        return groups
    }
}

private struct SessionDayGroup: Identifiable {
    let id: String
    let title: String?
    let sessions: [PiSavedSession]
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(10))
                .foregroundStyle(selected ? .white : Theme.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    selected ? Theme.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(selected ? Color.clear : Color(red: 223 / 255, green: 227 / 255, blue: 232 / 255), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct SessionListRow: View {
    let session: PiSavedSession
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.projectName)
                        .font(Theme.sans(12.5, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Theme.ink : Theme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(session.clockLabel)
                        .font(Theme.mono(10))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.dim)
                }
                Text(PiFormat.path(session.locationLabel))
                    .font(Theme.mono(9.5))
                    .foregroundStyle(isSelected ? Theme.faint : Theme.pale)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Theme.wash : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? Theme.accent : Color.clear)
                    .frame(width: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SessionConversationPanel: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showActivityDrawer: Bool

    var body: some View {
        VStack(spacing: 0) {
            SessionToolbar(showActivityDrawer: $showActivityDrawer)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if appState.messages.isEmpty && appState.uiRequest == nil {
                            VStack(spacing: 8) {
                                Text(appState.isPiRunning ? "Start a conversation with Pi" : "Connect Pi to start a session")
                                    .font(Theme.sans(15, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text("Prompts, streamed replies, and extension requests appear here.")
                                    .font(Theme.sans(12.5))
                                    .foregroundStyle(Theme.faint)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        } else {
                            ForEach(appState.messages) { message in
                                ChatMessageBubble(message: message)
                                    .id(message.id)
                            }
                            if let request = appState.uiRequest {
                                ExtensionUIRequestCard(request: request)
                                    .id("ui-request")
                            }
                            if !showActivityDrawer, let running = appState.activities.last(where: { $0.state == .running }) {
                                InlineToolChip(activity: running)
                            } else if !showActivityDrawer, let last = appState.activities.last {
                                InlineToolChip(activity: last)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                    .frame(maxWidth: showActivityDrawer ? .infinity : 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: appState.messages.count) { _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: appState.messages.last?.text) { _ in
                    scrollToBottom(proxy)
                }
            }

            ComposerBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = appState.messages.last {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

struct SessionToolbar: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showActivityDrawer: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.sessionName)
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(appState.messages.count) messages")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 0)

            if !appState.availableModels.isEmpty {
                Menu {
                    ForEach(appState.availableModels) { model in
                        Button {
                            appState.selectModel(model)
                        } label: {
                            HStack {
                                Text(model.displayName)
                                if model.identity == appState.sessionModel {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    OutlineControl(text: appState.sessionModel)
                }
                .menuStyle(.borderlessButton)
            }

            Menu {
                ForEach(["off", "minimal", "low", "medium", "high", "xhigh", "max"], id: \.self) { level in
                    Button {
                        appState.selectThinkingLevel(level)
                    } label: {
                        HStack {
                            Text(level)
                            if level == appState.thinkingLevel {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                OutlineControl(text: "think: \(appState.thinkingLevel)", muted: true)
            }
            .menuStyle(.borderlessButton)

            if appState.isGenerating {
                Button("Stop") {
                    appState.stopGeneration()
                }
                .font(Theme.sans(11.5))
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Theme.stopLine, lineWidth: 1)
                )
                .buttonStyle(.plain)
            }

            Button("New session") {
                appState.startNewSession()
            }
            .font(Theme.sans(11.5, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .buttonStyle(.plain)

            if !showActivityDrawer {
                Button {
                    showActivityDrawer = true
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .help("Show agent activity")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

struct OutlineControl: View {
    let text: String
    var muted = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(Theme.mono(10.5))
                .foregroundStyle(muted ? Theme.muted : Theme.ink)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Theme.pale)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(red: 223 / 255, green: 227 / 255, blue: 232 / 255), lineWidth: 1)
        )
    }
}

struct ChatMessageBubble: View {
    let message: PiChatMessage

    var body: some View {
        if message.isUser {
            VStack(alignment: .trailing, spacing: 7) {
                Text("You")
                    .font(Theme.mono(9.5))
                    .tracking(1.2)
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                Text(message.text)
                    .font(Theme.sans(13.5))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Theme.userBubble, in: UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9, bottomTrailingRadius: 3, topTrailingRadius: 9))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pi")
                    .font(Theme.mono(9.5))
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent)
                    .textCase(.uppercase)
                HStack(alignment: .bottom, spacing: 3) {
                    Text(message.text.isEmpty && message.isStreaming ? " " : message.text)
                        .font(Theme.sans(13.5))
                        .foregroundStyle(Theme.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if message.isStreaming {
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: 7, height: 15)
                            .opacity(0.85)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 24)
        }
    }
}

struct InlineToolChip: View {
    let activity: PiActivity

    var body: some View {
        HStack(spacing: 9) {
            PulseDot(
                color: activity.state == .running ? Theme.accent : (activity.state == .failed ? Theme.danger : Theme.positive),
                animated: activity.state == .running
            )
            Text("\(activity.toolName) · \(activity.detail)")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            if let duration = activity.durationLabel {
                Text(duration)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}

struct ComposerBar: View {
    @EnvironmentObject private var appState: AppState
    @State private var commandSelection = 0
    @State private var commandPaletteDismissed = false

    private var contextPercent: Double {
        (appState.usageStore.sessionUsage.contextPercent ?? 0) / 100
    }

    private var commandQuery: String? {
        guard appState.composerText.hasPrefix("/") else { return nil }
        let query = String(appState.composerText.dropFirst())
        guard !query.contains(where: { $0.isWhitespace }) else { return nil }
        return query.lowercased()
    }

    private var matchingCommands: [PiSlashCommand] {
        guard let commandQuery, !commandPaletteDismissed else { return [] }
        return appState.availableCommands.filter {
            commandQuery.isEmpty || $0.name.lowercased().hasPrefix(commandQuery)
        }
    }

    private var selectedCommand: PiSlashCommand? {
        guard !matchingCommands.isEmpty else { return nil }
        return matchingCommands[min(commandSelection, matchingCommands.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !matchingCommands.isEmpty {
                SlashCommandPalette(
                    commands: Array(matchingCommands.prefix(8)),
                    selection: min(commandSelection, max(0, min(7, matchingCommands.count - 1)))
                ) { command in
                    appState.insertSlashCommand(command)
                    commandPaletteDismissed = true
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Pi…", text: $appState.composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(13.5))
                    .lineLimit(1...6)
                    .onSubmit { submit() }

                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Send")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color(red: 216 / 255, green: 221 / 255, blue: 227 / 255), lineWidth: 1)
            )

            HStack(spacing: 12) {
                Text("stats synced from pi rpc")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.pale)
                Spacer()
                if let percent = appState.usageStore.sessionUsage.contextPercent {
                    Text(PiFormat.percent(percent) + " context")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.muted)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.hairline)
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: geo.size.width * CGFloat(min(max(contextPercent, 0), 1)))
                        }
                    }
                    .frame(width: 70, height: 3)
                }
                Button("Compact") {
                    appState.compactSession()
                }
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color(red: 223 / 255, green: 227 / 255, blue: 232 / 255), lineWidth: 1)
                )
                .buttonStyle(.plain)
                .disabled(!appState.isPiRunning || appState.isGenerating)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .overlay(alignment: .top) { Hairline() }
        .background {
            CommandPaletteKeyMonitor(isActive: !matchingCommands.isEmpty) { keyCode in
                switch keyCode {
                case 126:
                    commandSelection = max(0, commandSelection - 1)
                    return true
                case 125:
                    commandSelection = min(min(7, matchingCommands.count - 1), commandSelection + 1)
                    return true
                case 53:
                    commandPaletteDismissed = true
                    return true
                default:
                    return false
                }
            }
        }
        .onChange(of: appState.composerText) { value in
            commandSelection = 0
            if !value.hasPrefix("/") || value == "/" || !value.contains(where: { $0.isWhitespace }) {
                commandPaletteDismissed = false
            }
        }
    }

    private func submit() {
        if let command = selectedCommand {
            appState.insertSlashCommand(command)
            commandPaletteDismissed = true
        } else {
            appState.sendPrompt()
        }
    }
}

private struct CommandPaletteKeyMonitor: NSViewRepresentable {
    let isActive: Bool
    let handleKeyCode: (UInt16) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isActive: isActive, handleKeyCode: handleKeyCode)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.handleKeyCode = handleKeyCode
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var isActive: Bool
        var handleKeyCode: (UInt16) -> Bool
        private var monitor: Any?

        init(isActive: Bool, handleKeyCode: @escaping (UInt16) -> Bool) {
            self.isActive = isActive
            self.handleKeyCode = handleKeyCode
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isActive, self.handleKeyCode(event.keyCode) else { return event }
                return nil
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit { stop() }
    }
}

private struct SlashCommandPalette: View {
    let commands: [PiSlashCommand]
    let selection: Int
    let choose: (PiSlashCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("COMMANDS")
                    .font(Theme.mono(9))
                    .tracking(1.1)
                    .foregroundStyle(Theme.pale)
                Spacer()
                Text("↑↓ select · ↩ insert · esc close")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.pale)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)

            Hairline()

            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                Button {
                    choose(command)
                } label: {
                    HStack(spacing: 10) {
                        Text(command.invocation)
                            .font(Theme.mono(11, weight: .medium))
                            .foregroundStyle(index == selection ? Theme.accentInk : Theme.ink)
                            .frame(width: 118, alignment: .leading)
                            .lineLimit(1)
                        Text(command.description.isEmpty ? "No description" : command.description)
                            .font(Theme.sans(11))
                            .foregroundStyle(index == selection ? Theme.secondary : Theme.muted)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(command.sourceLabel)
                            .font(Theme.mono(8.5))
                            .foregroundStyle(index == selection ? Theme.accent : Theme.pale)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(index == selection ? Theme.accentFill : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.07), radius: 10, y: 4)
    }
}

struct AgentActivityPanel: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showActivityDrawer: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agent activity")
                    .font(Theme.sans(12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(appState.activities.count) tool\(appState.activities.count == 1 ? "" : "s")")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
                Button {
                    showActivityDrawer = false
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
                .help("Hide activity")
            }
            .padding(14)
            .overlay(alignment: .bottom) { Hairline() }

            if appState.activities.isEmpty {
                Text("Tool calls from this turn will appear here.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.faint)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(appState.activities.reversed()) { activity in
                            ActivityRow(activity: activity)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                MonoLabel(text: "This session", size: 9.5)
                HStack {
                    Text("tokens").foregroundStyle(Theme.muted)
                    Spacer()
                    Text(PiFormat.tokens(appState.usageStore.sessionUsage.totalTokens)).foregroundStyle(Theme.ink)
                }
                .font(Theme.mono(11))
                HStack {
                    Text("cost").foregroundStyle(Theme.muted)
                    Spacer()
                    Text(PiFormat.cost(appState.usageStore.sessionUsage.cost)).foregroundStyle(Theme.ink)
                }
                .font(Theme.mono(11))
            }
            .padding(14)
            .overlay(alignment: .top) { Hairline() }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }
}

struct ActivityRow: View {
    let activity: PiActivity

    private var dotColor: Color {
        switch activity.state {
        case .running: Theme.accent
        case .completed: Theme.positive
        case .failed: Theme.dangerFill
        }
    }

    private var stateLabel: String {
        switch activity.state {
        case .running: "running"
        case .completed: activity.durationLabel ?? "done"
        case .failed: "failed"
        }
    }

    private var stateColor: Color {
        switch activity.state {
        case .running: Theme.accent
        case .completed: Theme.dim
        case .failed: Theme.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PulseDot(color: dotColor, animated: activity.state == .running)
                Text(activity.toolName)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(activity.state == .running ? Theme.ink : Theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(stateLabel)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(stateColor)
            }
            if !activity.detail.isEmpty {
                Text(activity.detail)
                    .font(Theme.mono(10))
                    .foregroundStyle(activity.state == .running ? Theme.muted : Theme.dim)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            activity.state == .running ? Theme.wash : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}

struct ExtensionUIRequestCard: View {
    @EnvironmentObject private var appState: AppState
    let request: PiUIRequest
    @State private var inputText: String

    init(request: PiUIRequest) {
        self.request = request
        _inputText = State(initialValue: request.prefill)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                PulseDot(color: Theme.accent, animated: false)
                Text("Extension · \(request.method)")
                    .font(Theme.mono(10))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
            }

            if !request.title.isEmpty {
                Text(request.title)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            if !request.message.isEmpty {
                Text(request.message)
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch request.method {
            case "confirm":
                HStack(spacing: 7) {
                    optionButton("Cancel") { appState.respondToUIRequest(confirmed: false) }
                    optionButton("Confirm", emphasized: true) { appState.respondToUIRequest(confirmed: true) }
                }
            case "select":
                HStack(spacing: 7) {
                    ForEach(Array(request.options.enumerated()), id: \.offset) { _, option in
                        optionButton(option) { appState.respondToUIRequest(value: option) }
                    }
                    optionButton("Cancel", muted: true) { appState.respondToUIRequest(cancelled: true) }
                }
            case "input", "editor":
                if request.method == "editor" {
                    TextEditor(text: $inputText)
                        .font(Theme.mono(11))
                        .frame(minHeight: 90)
                        .padding(6)
                        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Theme.line, lineWidth: 1)
                        )
                } else {
                    TextField(request.placeholder.isEmpty ? "Value" : request.placeholder, text: $inputText)
                        .textFieldStyle(.plain)
                        .font(Theme.sans(12.5))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Theme.line, lineWidth: 1)
                        )
                }
                HStack(spacing: 7) {
                    optionButton("Cancel") { appState.respondToUIRequest(cancelled: true) }
                    optionButton("Submit", emphasized: true) { appState.respondToUIRequest(value: inputText) }
                }
            default:
                optionButton("Dismiss") { appState.respondToUIRequest(cancelled: true) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(red: 223 / 255, green: 227 / 255, blue: 232 / 255), lineWidth: 1)
        )
    }

    private func optionButton(_ title: String, emphasized: Bool = false, muted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(Theme.sans(12))
            .foregroundStyle(muted ? Theme.dim : Theme.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(emphasized ? Theme.canvas : Theme.canvas, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(muted ? Color.clear : Color(red: 223 / 255, green: 227 / 255, blue: 232 / 255), lineWidth: 1)
            )
            .buttonStyle(.plain)
    }
}
