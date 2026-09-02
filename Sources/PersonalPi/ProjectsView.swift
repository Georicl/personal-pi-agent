import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom, spacing: 16) {
                Text("Projects")
                    .font(Theme.serif(30))
                    .foregroundStyle(Theme.ink)
                Text("Local directories Pi can work in. Switching scope restarts the runtime.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.faint)
                    .padding(.bottom, 3)
                Spacer()
                Menu {
                    Button("Create project…") { appState.createWorkspace() }
                    Button("Add existing project…") { appState.addExistingWorkspace() }
                } label: {
                    Text("New project")
                        .font(Theme.sans(11.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 0) {
                ProjectStatCell(label: "Projects", value: "\(appState.workspaces.count)", showsLeadingRule: false)
                ProjectStatCell(label: "Sessions", value: "\(appState.workspaces.reduce(0) { $0 + $1.sessionCount })")
                ProjectStatCell(label: "Current scope", value: appState.scopeTitle)
            }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            if appState.workspaces.isEmpty {
                Text("Create a project or add an existing folder.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.faint)
                    .padding(.vertical, 20)
                    .overlay(alignment: .top) { Hairline(color: Theme.rule) }
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.workspaces) { project in
                        RegisteredProjectRow(
                            project: project,
                            isSelected: appState.workspaceScope == .workspace && appState.workspace.path == project.path
                        ) {
                            appState.selectWorkspace(project)
                            appState.selectedSection = .overview
                        }
                    }
                }
                .overlay(alignment: .bottom) { Hairline(color: Theme.rule) }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: 980, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            appState.refreshSavedSessions()
        }
    }
}

struct ProjectStatCell: View {
    let label: String
    let value: String
    var showsLeadingRule = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(label))
                .textCase(.uppercase)
                .font(Theme.mono(9.5))
                .tracking(1.2)
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(Theme.mono(18))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if showsLeadingRule {
                Hairline(axis: .vertical, color: Color(red: 232 / 255, green: 234 / 255, blue: 238 / 255))
            }
        }
    }
}

struct RegisteredProjectRow: View {
    let project: PiWorkspace
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(project.name)
                            .font(Theme.sans(13.5, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(Theme.ink)
                        if isSelected {
                            Text("CURRENT")
                                .font(Theme.mono(9, weight: .medium))
                                .tracking(1)
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.wash, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                    }
                    Text(PiFormat.path(project.path))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    if project.git.isRepository {
                        Text(project.branchLabel)
                            .foregroundStyle(Theme.muted)
                        Text("·")
                            .foregroundStyle(Theme.hairline)
                        Text(project.git.isClean ? "clean" : "\(project.git.changedFiles) changed")
                            .foregroundStyle(project.git.isClean ? Theme.positive : Theme.warning)
                    } else {
                        Text("not a git repo")
                            .foregroundStyle(Theme.dim)
                    }
                    Text("·")
                        .foregroundStyle(Theme.hairline)
                    Text("\(project.sessionCount)")
                        .foregroundStyle(isSelected ? Theme.accent : Theme.dim)
                }
                .font(Theme.mono(10))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .background(isSelected ? Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255) : Color.clear)
            .overlay(alignment: .top) { Hairline(color: Theme.rule) }
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(Theme.accent).frame(width: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
