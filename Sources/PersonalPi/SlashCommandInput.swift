import SwiftUI
import AppKit

struct SlashCommandInput: View {
    @EnvironmentObject private var appState: AppState

    let placeholder: LocalizedStringKey
    var maximumLines = 6
    var inputBackground = Theme.panel
    var sendButtonSize: CGFloat = 26

    @State private var commandSelection = 0
    @State private var commandPaletteDismissed = false

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
                    commands: matchingCommands,
                    selection: min(commandSelection, matchingCommands.count - 1)
                ) { command in
                    appState.insertSlashCommand(command)
                    commandPaletteDismissed = true
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $appState.composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(13.5))
                    .lineLimit(1...maximumLines)
                    .onSubmit { submit() }
                    .accessibilityIdentifier("composer-input")

                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: sendButtonSize, height: sendButtonSize)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Send")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color(red: 216 / 255, green: 221 / 255, blue: 227 / 255), lineWidth: 1)
            )
        }
        .background {
            CommandPaletteKeyMonitor(isActive: !matchingCommands.isEmpty) { keyCode in
                switch keyCode {
                case 126:
                    commandSelection = max(0, commandSelection - 1)
                    return true
                case 125:
                    commandSelection = min(matchingCommands.count - 1, commandSelection + 1)
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
                Text("COMMANDS · \(commands.count)")
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

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: commands.count > 7) {
                    LazyVStack(spacing: 0) {
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
                                    Group {
                                        if command.source == "native" {
                                            Text(LocalizedStringKey(
                                                command.description.isEmpty
                                                    ? "No description"
                                                    : command.description
                                            ))
                                        } else {
                                            Text(command.description.isEmpty ? "No description" : command.description)
                                        }
                                    }
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
                            .accessibilityIdentifier("slash-command-\(command.name)")
                            .id(command.id)
                        }
                    }
                }
                .frame(maxHeight: 248)
                .onChange(of: selection) { newSelection in
                    guard commands.indices.contains(newSelection) else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(commands[newSelection].id, anchor: .center)
                    }
                }
            }
        }
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.07), radius: 10, y: 4)
    }
}
