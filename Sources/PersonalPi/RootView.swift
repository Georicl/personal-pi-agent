import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            WindowChrome()
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 238)
                Hairline(axis: .vertical)
                DetailView()
            }
        }
        .background(Theme.canvas)
        .tint(Theme.accent)
        .task {
            appState.usageStore.refresh()
            appState.refreshSavedSessions()
        }
    }
}

struct WindowChrome: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("Personal Pi")
                .font(Theme.serif(15))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
        }
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 38)
        .background(Theme.chrome)
        .overlay(alignment: .bottom) {
            Hairline()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScopeSwitcher()
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    SidebarProjects()
                    SidebarNavigation()
                    SidebarRecentSessions()
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }

            ConnectionCard()
                .padding(12)
                .overlay(alignment: .top) { Hairline() }
        }
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }
}

struct ScopeSwitcher: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Menu {
            Section("PROJECTS") {
                ForEach(appState.workspaces) { workspace in
                    Button {
                        appState.selectWorkspace(workspace)
                    } label: {
                        HStack {
                            Label(workspace.name, systemImage: "folder")
                            if appState.workspaceScope == .workspace && appState.workspace.path == workspace.path {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                appState.selectGlobalScope()
            } label: {
                HStack {
                    Label("Global Chat", systemImage: "bubble.left.and.bubble.right")
                    if appState.workspaceScope == .global {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            Button {
                appState.createWorkspace()
            } label: {
                Label("Create project…", systemImage: "folder.badge.plus")
            }
            Button {
                appState.addExistingWorkspace()
            } label: {
                Label("Add existing project…", systemImage: "folder")
            }
        } label: {
            HStack(spacing: 10) {
                Text(String(appState.scopeTitle.prefix(1)).uppercased())
                    .font(Theme.mono(11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22, height: 22)
                    .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Theme.accentSoft, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.scopeTitle)
                        .font(Theme.sans(13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(appState.workspaceScope == .global ? "Temporary chat" : "Current project")
                        .font(Theme.sans(10.5))
                        .foregroundStyle(Theme.faint)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.pale)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(red: 223 / 255, green: 227 / 255, blue: 232 / 255), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 1, y: 1)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }
}

struct SidebarProjects: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                MonoLabel(text: "Projects", size: 9.5)
                Spacer()
                Button {
                    appState.refreshSavedSessions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
                .help("Refresh projects")

                Menu {
                    Button("Create project") { appState.createWorkspace() }
                    Button("Add existing project") { appState.addExistingWorkspace() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                .menuStyle(.borderlessButton)
                .help("New project")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            ForEach(appState.workspaces) { workspace in
                SidebarProjectRow(
                    workspace: workspace,
                    isSelected: appState.workspaceScope == .workspace && appState.workspace.path == workspace.path
                ) {
                    appState.selectWorkspace(workspace)
                }
            }

            Button {
                appState.selectGlobalScope()
            } label: {
                Text("Global Chat")
                    .font(Theme.sans(12))
                    .foregroundStyle(appState.workspaceScope == .global ? Theme.ink : Theme.faint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        appState.workspaceScope == .global ? Theme.canvas : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(appState.workspaceScope == .global ? Theme.accentSoft : Color.clear, lineWidth: 1)
                    )
                    .overlay(alignment: .leading) {
                        if appState.workspaceScope == .global {
                            Rectangle()
                                .fill(Theme.accent)
                                .frame(width: 2)
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                        }
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

struct SidebarProjectRow: View {
    let workspace: PiWorkspace
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(workspace.name)
                        .font(Theme.sans(12.5, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Theme.ink : Theme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(workspace.sessionCount)")
                        .font(Theme.mono(10))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.dim)
                }
                HStack(spacing: 7) {
                    if workspace.git.isRepository {
                        Text(workspace.branchLabel)
                            .foregroundStyle(isSelected ? Theme.muted : Theme.dim)
                        Text("·")
                            .foregroundStyle(Theme.hairline)
                        Text(workspace.git.isClean ? "clean" : "\(workspace.git.changedFiles) changed")
                            .foregroundStyle(workspace.git.isClean ? Theme.positive : Theme.warning)
                    } else {
                        Text("not a git repo")
                            .foregroundStyle(Theme.dim)
                    }
                }
                .font(Theme.mono(10))
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Theme.canvas : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? Theme.accentSoft : Color.clear, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 2)
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct SidebarNavigation: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            MonoLabel(text: "Navigation", size: 9.5)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            ForEach(AppSection.allCases) { section in
                SidebarRow(
                    section: section,
                    isSelected: appState.selectedSection == section,
                    badge: section == .tasks ? appState.taskStore.unreadCount : 0
                ) {
                    appState.selectedSection = section
                }
            }
        }
    }
}

struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.pale)
                    .frame(width: 14)
                Text(section.title)
                    .font(Theme.sans(13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.secondary)
                Spacer(minLength: 0)
                if badge > 0 {
                    Text("\(badge)")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isSelected ? Theme.selected : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SidebarRecentSessions: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                MonoLabel(text: "Recent", size: 9.5)
                Spacer()
                Button("View all") {
                    appState.showAllSessions()
                }
                .font(Theme.sans(10.5))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            if appState.sidebarSessions.isEmpty {
                Text("No saved sessions")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.faint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(appState.sidebarSessions.prefix(6))) { session in
                    Button {
                        appState.selectedSection = .sessions
                        appState.sessionProjectFilter = session.cwd
                        appState.switchSession(session)
                    } label: {
                        HStack {
                            Text(session.projectName)
                                .font(Theme.sans(12.5))
                                .foregroundStyle(session.id == appState.sessionId ? Theme.ink : Theme.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(session.clockLabel)
                                .font(Theme.mono(10))
                                .foregroundStyle(session.id == appState.sessionId ? Theme.muted : Theme.dim)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            session.id == appState.sessionId ? Theme.selected : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ConnectionCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            if !appState.isPiRunning {
                appState.connectPi()
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(appState.connectionState.color)
                        .frame(width: 6, height: 6)
                    Text(appState.connectionState.label)
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
                if let detail = appState.connectionState.detail {
                    Text(detail)
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.danger)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(appState.shortenedScopePath)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(red: 223 / 255, green: 227 / 255, blue: 232 / 255), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(appState.isPiRunning)
        .help(appState.isPiRunning ? appState.scopePathLabel : "Connect to Pi")
    }
}

struct DetailView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            switch appState.selectedSection {
            case .overview:
                ScrollView(showsIndicators: false) {
                    OverviewView()
                }
            case .sessions:
                SessionsView()
            case .knowledge:
                ScrollView(showsIndicators: false) {
                    KnowledgeView()
                }
            case .projects:
                ScrollView(showsIndicators: false) {
                    ProjectsView()
                }
            case .tasks:
                ScrollView(showsIndicators: false) {
                    TasksView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}

struct TopBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Text(appState.selectedSection.title)
                .font(Theme.sans(12.5))
                .foregroundStyle(Theme.muted)

            AgentStatusPill()

            Spacer(minLength: 0)

            Text(PiFormat.todayLabel())
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.dim)

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.connectionState.color)
                    .frame(width: 5, height: 5)
                Text(appState.connectionState.label)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Hairline(color: Theme.rule) }
    }
}

struct AgentStatusPill: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 7) {
            PulseDot(
                color: appState.isAgentBusy ? Theme.accent : Theme.idle,
                animated: appState.isAgentBusy
            )
            Text(appState.agentStatusCaption)
                .font(Theme.mono(10.5))
                .foregroundStyle(appState.isAgentBusy ? Theme.accentInk : Theme.dim)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(appState.isAgentBusy ? Theme.wash : Color.clear, in: Capsule())
        .overlay(
            Capsule().stroke(appState.isAgentBusy ? Theme.accentSoft : Theme.line, lineWidth: 1)
        )
    }
}
