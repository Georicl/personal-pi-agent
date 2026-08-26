import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TaskListContent(store: appState.taskStore)
    }
}

struct TaskListContent: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: PiTaskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom, spacing: 16) {
                Text("Tasks")
                    .font(Theme.serif(30))
                    .foregroundStyle(Theme.ink)
                Text("One task per session — later prompts update the same task.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.faint)
                    .padding(.bottom, 3)
            }

            HStack(spacing: 0) {
                TaskStatCell(label: "Submitted", count: count(.submitted), emphasis: .plain)
                TaskStatCell(label: "Running", count: count(.running), emphasis: .running)
                TaskStatCell(label: "Waiting", count: count(.waiting), emphasis: .waiting)
                TaskStatCell(label: "Finished", count: count(.finished), emphasis: .plain)
                TaskStatCell(label: "Unseen", count: store.unreadCount, emphasis: .plain)
            }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            if store.tasks.isEmpty {
                Text("Every prompt submitted to Pi will appear here.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.faint)
                    .padding(.vertical, 20)
                    .overlay(alignment: .top) { Hairline(color: Theme.rule) }
            } else {
                VStack(spacing: 0) {
                    ForEach(store.tasks) { task in
                        TaskRecordRow(task: task) {
                            appState.openTask(task)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: 980, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func count(_ state: PiTaskState) -> Int {
        store.tasks.filter { $0.state == state }.count
    }
}

enum TaskStatEmphasis {
    case plain
    case running
    case waiting
}

struct TaskStatCell: View {
    let label: String
    let count: Int
    let emphasis: TaskStatEmphasis

    private var labelColor: Color {
        switch emphasis {
        case .plain: Theme.dim
        case .running: Theme.accent
        case .waiting: Theme.warning
        }
    }

    private var valueColor: Color {
        switch emphasis {
        case .plain: Theme.ink
        case .running: Theme.accent
        case .waiting: Theme.warning
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(Theme.mono(9.5))
                .tracking(1.2)
                .foregroundStyle(labelColor)
            Text("\(count)")
                .font(Theme.mono(22))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(emphasis == .running ? Theme.canvas : Color.clear)
        .overlay(alignment: .leading) {
            if emphasis != .plain || label != "Submitted" {
                Hairline(axis: .vertical, color: Color(red: 232 / 255, green: 234 / 255, blue: 238 / 255))
            }
        }
    }
}

struct TaskRecordRow: View {
    let task: PiTaskRecord
    let action: () -> Void

    private var dotColor: Color {
        switch task.state {
        case .submitted: Theme.idle
        case .running: Theme.accent
        case .waiting: Color(red: 201 / 255, green: 162 / 255, blue: 74 / 255)
        case .finished:
            if task.detail.localizedCaseInsensitiveContains("interrupt") || task.detail.localizedCaseInsensitiveContains("error") {
                Color(red: 217 / 255, green: 154 / 255, blue: 154 / 255)
            } else {
                Theme.idle
            }
        }
    }

    private var stateForeground: Color {
        switch task.state {
        case .running: Theme.accentInk
        case .waiting: Color(red: 138 / 255, green: 106 / 255, blue: 28 / 255)
        default: Theme.muted
        }
    }

    private var stateBackground: Color {
        switch task.state {
        case .running: Theme.wash
        case .waiting: Theme.warningFill
        default: Color(red: 244 / 255, green: 245 / 255, blue: 247 / 255)
        }
    }

    private var stateBorder: Color {
        switch task.state {
        case .running: Theme.accentSoft
        case .waiting: Theme.warningLine
        default: Theme.line
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                PulseDot(color: dotColor, animated: task.state == .running)
                    .padding(.leading, 6)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(task.title)
                            .font(Theme.sans(13.5))
                            .foregroundStyle(task.state == .finished ? Theme.secondary : Theme.ink)
                            .lineLimit(1)
                        if task.hasUnreadUpdate {
                            Text("NEW")
                                .font(Theme.mono(9, weight: .medium))
                                .tracking(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                    }
                    HStack(spacing: 10) {
                        Text(task.scopeName)
                            .foregroundStyle(task.state == .running ? Theme.accent : Theme.dim)
                        Text("·")
                        Text(task.detail)
                            .foregroundStyle(
                                task.detail.localizedCaseInsensitiveContains("interrupt")
                                    ? Theme.danger
                                    : Theme.dim
                            )
                    }
                    .font(Theme.mono(10))
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(task.state.title)
                    .font(Theme.mono(10))
                    .foregroundStyle(stateForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stateBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(stateBorder, lineWidth: 1)
                    )

                Text(PiFormat.relative(task.updatedAt))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 64, alignment: .trailing)
                    .padding(.trailing, 6)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
            .background(task.state == .running ? Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255) : Color.clear)
            .overlay(alignment: .top) { Hairline(color: Theme.rule) }
        }
        .buttonStyle(.plain)
    }
}
