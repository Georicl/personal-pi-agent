import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 218, ideal: 238, max: 270)
        } detail: {
            DetailView()
        }
        .tint(Theme.accent)
        .background(Theme.canvas)
        .task {
            appState.usageStore.refresh()
            appState.refreshSavedSessions()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScopeSwitcher()
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 22)

            HStack {
                Text("PROJECTS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Theme.sidebarSecondary)
                Spacer()
                Menu {
                    Button {
                        appState.createWorkspace()
                    } label: {
                        Label("Create project", systemImage: "folder.badge.plus")
                    }
                    Button {
                        appState.addExistingWorkspace()
                    } label: {
                        Label("Add existing project", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.sidebarSecondary)
                }
                .menuStyle(.borderlessButton)
                .help("New project")
                Button {
                    appState.refreshSavedSessions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.sidebarSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh projects")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 9)

            SidebarWorkspaceList()
                .padding(.horizontal, 10)
                .padding(.bottom, 14)

            Text("NAVIGATION")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Theme.sidebarSecondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 7)

            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    if section == .tasks {
                        TaskSidebarRow(
                            store: appState.taskStore,
                            isSelected: appState.selectedSection == section
                        ) {
                            appState.selectedSection = section
                        }
                    } else {
                        SidebarRow(section: section, isSelected: appState.selectedSection == section) {
                            appState.selectedSection = section
                        }
                    }
                }
            }
            .padding(.horizontal, 10)

            SidebarWorkspaceSessions()
                .padding(.top, 18)
                .padding(.horizontal, 14)

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.connectionState.color)
                        .frame(width: 8, height: 8)
                    Text(appState.connectionState.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                }

                Text(appState.scopePathLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.sidebarSecondary)
                    .lineLimit(2)

                Button {
                    appState.connectPi()
                } label: {
                    Label("Connect to Pi", systemImage: "bolt.horizontal.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.25))
            }
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(14)
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
                            Label(workspace.name, systemImage: "folder.fill")
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
                    Label("Global Chat", systemImage: "bubble.left.and.bubble.right.fill")
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
                Image(systemName: appState.workspaceScope.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.scopeTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(appState.workspaceScope == .global ? "Temporary chat" : "Current project")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.sidebarSecondary)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.sidebarSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
    }
}

struct SidebarWorkspaceList: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(appState.workspaces) { workspace in
                Button {
                    appState.selectWorkspace(workspace)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(appState.workspaceScope == .workspace && appState.workspace.path == workspace.path ? .white : Theme.accent)
                            .frame(width: 24, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Label(workspace.branchLabel, systemImage: "arrow.triangle.branch")
                                Text("·")
                                Text(workspace.git.summary)
                            }
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(
                                workspace.git.isClean
                                    ? Color.green.opacity(0.88)
                                    : Theme.sidebarSecondary
                            )
                            .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(workspace.sessionCount)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("sessions")
                                .font(.system(size: 7, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(Theme.sidebarSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(minHeight: 52)
                    .background(
                        appState.workspaceScope == .workspace && appState.workspace.path == workspace.path
                            ? Theme.accent.opacity(0.82)
                            : .white.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                appState.selectGlobalScope()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18)
                    Text("Global Chat")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(appState.workspaceScope == .global ? .white : Theme.sidebarSecondary)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(appState.workspaceScope == .global ? Theme.accent.opacity(0.82) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

struct TaskSidebarRow: View {
    @ObservedObject var store: PiTaskStore
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                Text("Tasks")
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Spacer()
                if store.unreadCount > 0 {
                    Text("\(store.unreadCount)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? Theme.accent : .white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isSelected ? .white : Theme.accent, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? .white : Theme.sidebarSecondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(isSelected ? Theme.accent.opacity(0.92) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SidebarWorkspaceSessions: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("RECENT SESSIONS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Theme.sidebarSecondary)
                Spacer()
                Text("\(appState.sidebarSessions.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.sidebarSecondary)
            }

            if appState.sidebarSessions.isEmpty {
                Text("No saved sessions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.sidebarSecondary)
                    .padding(.vertical, 5)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(appState.sidebarSessions.prefix(6))) { session in
                            SidebarSessionRow(
                                session: session,
                                isSelected: session.id == appState.sessionId
                            ) {
                                appState.selectedSection = .sessions
                                appState.sessionProjectFilter = session.cwd
                                appState.switchSession(session)
                            }
                        }
                    }
                }
            }

            Button {
                appState.showAllSessions()
            } label: {
                HStack(spacing: 5) {
                    Text("View all sessions")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
            }
            .buttonStyle(.plain)
        }
    }
}

struct WorkspaceSidebarCard: View {
    let workspace: PiWorkspace
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 29, height: 29)
                        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("Workspace")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.sidebarSecondary)
                    }
                    Spacer(minLength: 0)
                }

                Text(workspace.path)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.sidebarSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Label(workspace.branchLabel, systemImage: "arrow.triangle.branch")
                    Spacer(minLength: 0)
                    Text(workspace.git.summary)
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(workspace.git.isClean ? .green.opacity(0.9) : Theme.orange)

                HStack(spacing: 9) {
                    WorkspaceMeta(icon: "bubble.left.and.bubble.right", value: "\(workspace.sessionCount)")
                    WorkspaceMeta(icon: "folder", value: "\(workspace.projectCount)")
                    Spacer(minLength: 0)
                    Text(workspace.configurationSummary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.sidebarSecondary)
            }
            .padding(12)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceMeta: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(value)
        }
    }
}

struct SidebarSessionRow: View {
    let session: PiSavedSession
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? .white : Theme.accent)
                    .frame(width: 5, height: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.projectName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : Theme.sidebarSecondary)
                        .lineLimit(1)
                    Text(session.title)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? .white.opacity(0.72) : Theme.sidebarSecondary.opacity(0.78))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Theme.accent.opacity(0.82) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? .white : Theme.sidebarSecondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(isSelected ? Theme.accent.opacity(0.92) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct DetailView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            ScrollView(showsIndicators: false) {
                switch appState.selectedSection {
                case .overview:
                    OverviewView()
                case .sessions:
                    SessionsView()
                case .knowledge:
                    KnowledgeView()
                case .projects:
                    ProjectsView()
                case .tasks:
                    TasksView()
                }
            }
        }
        .background(Theme.canvas)
    }
}

struct TopBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.selectedSection.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("Wednesday, August 26, 2026")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            HStack(spacing: 10) {
                StatusPill(state: appState.connectionState)
                Circle()
                    .fill(Theme.accent.opacity(0.16))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 20)
        .background(.white.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}

struct StatusPill: View {
    let state: PiConnectionState

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(state.color).frame(width: 7, height: 7)
            Text(state.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }
}

struct OverviewView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 7) {
                Text("Good afternoon,")
                    .foregroundStyle(Theme.muted)
                Text("Georic")
                    .foregroundStyle(Theme.ink)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))

            HStack(alignment: .top, spacing: 22) {
                HeroCard()
                FocusCard()
            }

            AccountUsageCard(usageStore: appState.usageStore)

            HStack {
                Text("Continue working")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("View all") {
                    appState.selectedSection = .sessions
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 14) {
                SessionCard(icon: "hammer.fill", tint: .orange, title: "Personal Pi Agent", detail: "Designing the native workspace", time: "Today")
                SessionCard(icon: "doc.text.magnifyingglass", tint: .blue, title: "Research workflow", detail: "Academic reading and evidence", time: "Yesterday")
                SessionCard(icon: "curlybraces", tint: .purple, title: "Chronicle", detail: "Astro architecture review", time: "Aug 20")
            }

            Text("Quick actions")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 14) {
                QuickAction(icon: "plus", title: "New session", subtitle: "Start a focused task") {
                    appState.startNewSession()
                }
                QuickAction(icon: "magnifyingglass", title: "Explore project", subtitle: "Read before changing") {
                    appState.selectedSection = .projects
                }
                QuickAction(icon: "book.closed", title: "Research topic", subtitle: "Search and synthesize") {
                    appState.selectedSection = .knowledge
                }
            }
        }
        .padding(34)
        .frame(maxWidth: 1080, alignment: .leading)
    }
}

struct KnowledgeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Knowledge libraries")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("Global knowledge is shared; project knowledge follows the selected project.")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }

            HStack(alignment: .top, spacing: 16) {
                KnowledgeScopeCard(
                    title: "Global knowledge",
                    subtitle: "Available in Global Chat and every project",
                    path: appState.globalKnowledgeDirectory,
                    fileCount: appState.globalKnowledgeFileCount,
                    icon: "globe",
                    tint: Theme.accent,
                    isAvailable: true,
                    action: appState.openGlobalKnowledge
                )

                KnowledgeScopeCard(
                    title: "Project knowledge",
                    subtitle: appState.workspaceScope == .workspace
                        ? "Private to \(appState.workspace.name)"
                        : "Select a project to use project knowledge",
                    path: appState.workspaceScope == .workspace
                        ? appState.projectKnowledgeDirectory
                        : "No project selected",
                    fileCount: appState.workspaceScope == .workspace
                        ? appState.projectKnowledgeFileCount
                        : 0,
                    icon: "folder.fill",
                    tint: Theme.orange,
                    isAvailable: appState.workspaceScope == .workspace,
                    action: appState.openProjectKnowledge
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Knowledge boundary", systemImage: "square.3.layers.3d")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("Files are stored outside the live prompt. Pi should retrieve them when needed instead of loading the entire library into every conversation.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .padding(34)
        .frame(maxWidth: 1080, alignment: .leading)
    }
}

struct KnowledgeScopeCard: View {
    let title: String
    let subtitle: String
    let path: String
    let fileCount: Int
    let icon: String
    let tint: Color
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }

            Text(path)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack {
                Label("\(fileCount) files", systemImage: "doc.text")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
                Spacer()
                Button("Open folder", action: action)
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.bordered)
                    .disabled(!isAvailable)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(.white.opacity(isAvailable ? 1 : 0.58), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct TasksView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TaskListContent(store: appState.taskStore)
    }
}

struct TaskListContent: View {
    @ObservedObject var store: PiTaskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Task activity")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("Submitted prompts, running work, waiting actions, and unseen completions")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }

            HStack(spacing: 12) {
                TaskStatCard(label: "Submitted", count: count(.submitted), tint: Theme.muted)
                TaskStatCard(label: "Running", count: count(.running), tint: .blue)
                TaskStatCard(label: "Waiting", count: count(.waiting), tint: Theme.orange)
                TaskStatCard(label: "Finished", count: count(.finished), tint: .green)
                TaskStatCard(label: "Unseen", count: store.unreadCount, tint: Theme.accent)
            }

            if store.tasks.isEmpty {
                PlaceholderView(
                    title: "No tasks yet",
                    subtitle: "Every prompt submitted to Pi will appear here.",
                    icon: "checklist"
                )
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(store.tasks) { task in
                        TaskRecordRow(task: task) {
                            store.markViewed(task)
                        }
                    }
                }
            }
        }
        .padding(34)
        .frame(maxWidth: 1080, alignment: .leading)
    }

    private func count(_ state: PiTaskState) -> Int {
        store.tasks.filter { $0.state == state }.count
    }
}

struct TaskStatCard: View {
    let label: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct TaskRecordRow: View {
    let task: PiTaskRecord
    let action: () -> Void

    private var tint: Color {
        switch task.state {
        case .submitted: Theme.muted
        case .running: .blue
        case .waiting: Theme.orange
        case .finished: .green
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: task.state.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(task.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if task.hasUnreadUpdate {
                            Text("NEW")
                                .font(.system(size: 7, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.accent, in: Capsule())
                        }
                    }
                    Text("\(task.scopeName)  ·  \(task.detail)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(task.state.title)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                    Text(task.updatedAt, style: .relative)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(task.hasUnreadUpdate ? Theme.accent.opacity(0.35) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ProjectsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your projects")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("Project overview, Git state, sessions, and quick switching")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Menu {
                    Button("Create project…") { appState.createWorkspace() }
                    Button("Add existing project…") { appState.addExistingWorkspace() }
                } label: {
                    Label("New project", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }

            HStack(spacing: 12) {
                ProjectStatCard(value: "\(appState.workspaces.count)", label: "Projects", icon: "folder.fill", tint: Theme.accent)
                ProjectStatCard(value: "\(appState.workspaces.reduce(0) { $0 + $1.sessionCount })", label: "Sessions", icon: "bubble.left.and.bubble.right.fill", tint: Theme.orange)
                ProjectStatCard(value: appState.scopeTitle, label: "Current scope", icon: "location.fill", tint: .blue)
            }

            if appState.workspaces.isEmpty {
                PlaceholderView(title: "No projects yet", subtitle: "Create a project or add an existing folder.", icon: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(appState.workspaces) { project in
                        RegisteredProjectCard(
                            project: project,
                            isSelected: appState.workspaceScope == .workspace && appState.workspace.path == project.path
                        ) {
                            appState.selectWorkspace(project)
                            appState.selectedSection = .overview
                        }
                    }
                }
            }
        }
        .padding(34)
        .frame(maxWidth: 1080, alignment: .leading)
        .task {
            appState.refreshSavedSessions()
        }
    }
}

struct RegisteredProjectCard: View {
    let project: PiWorkspace
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isSelected ? .white : Theme.accent)
                        .frame(width: 34, height: 34)
                        .background(isSelected ? .white.opacity(0.16) : Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text(project.path)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Text("CURRENT")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    Label(project.branchLabel, systemImage: "arrow.triangle.branch")
                    Text(project.git.summary)
                    Spacer()
                    Label("\(project.sessionCount)", systemImage: "bubble.left.and.bubble.right")
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(isSelected ? .white : Theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(isSelected ? Theme.accentGradient : LinearGradient(colors: [.white, .white], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(isSelected ? Color.clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ProjectStatCard: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 29, height: 29)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct ProjectCard: View {
    let project: PiProjectGroup
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 34, height: 34)
                        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text("\(project.sessions.count) session\(project.sessions.count == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }

                Text(project.locationLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack {
                    Text("Latest session")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(project.latestSession?.title ?? "—")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct SessionsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sessions")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("\(appState.visibleSessions.count) sessions  ·  \(appState.sessionName)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                HStack(spacing: 8) {
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
                            Label(appState.sessionModel, systemImage: "cpu")
                        }
                        .menuStyle(.borderlessButton)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                        Label("Thinking: \(appState.thinkingLevel)", systemImage: "brain.head.profile")
                    }
                    .menuStyle(.borderlessButton)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    if appState.isGenerating {
                        Button {
                            appState.stopGeneration()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    Button {
                        appState.startNewSession()
                    } label: {
                        Label("New session", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                SessionListPanel()
                    .frame(width: 250)
                SessionConversationPanel()
                    .frame(maxWidth: .infinity)
            }
            .frame(minHeight: 620, alignment: .top)
        }
        .padding(34)
        .frame(maxWidth: 1080, alignment: .leading)
        .task {
            appState.refreshSavedSessions()
        }
    }
}

struct SessionListPanel: View {
    @EnvironmentObject private var appState: AppState

    private var title: String {
        guard let path = appState.sessionProjectFilter else { return "All sessions" }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "Filtered sessions" : name
    }

    private var subtitle: String {
        if appState.sessionProjectFilter != nil { return "Filtered by project" }
        return appState.workspaceScope == .global ? "Global Chat sessions" : "Current project sessions"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if appState.sessionProjectFilter != nil {
                    Button("All") {
                        appState.showAllSessions()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
                Button {
                    appState.refreshSavedSessions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 26, height: 26)
                        .background(Theme.accent.opacity(0.09), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Refresh sessions")
            }

            Divider().overlay(Theme.line)

            if appState.visibleSessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "clock.badge.questionmark")
                        .foregroundStyle(Theme.accent)
                    Text("No saved sessions yet")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("Sessions created by Pi will appear here.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 12)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 7) {
                        ForEach(appState.visibleSessions) { session in
                            SessionListRow(
                                session: session,
                                isSelected: session.id == appState.sessionId
                            ) {
                                appState.switchSession(session)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct SessionListRow: View {
    let session: PiSavedSession
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Theme.accent)
                    Text(session.projectName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(session.title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? .white.opacity(0.88) : Theme.muted)
                Text(session.locationLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? .white.opacity(0.68) : Theme.muted.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.accent : Theme.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SessionConversationPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                if appState.messages.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Theme.accent)
                        Text(appState.isPiRunning ? "Start a conversation with Pi" : "Connect Pi to start a session")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Text("Your prompts, tool activity, and streamed responses will appear here.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(appState.messages) { message in
                        ChatMessageBubble(message: message)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 1))

            if let request = appState.uiRequest {
                ExtensionUIRequestCard(request: request)
            }

            if !appState.activities.isEmpty {
                ActivityTimeline(activities: appState.activities)
            }

            HStack(spacing: 10) {
                TextField("Ask Pi anything…", text: $appState.composerText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
                    .onSubmit { appState.sendPrompt() }

                Button {
                    appState.sendPrompt()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Session stats are synced from Pi RPC")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("Compact context") {
                    appState.compactSession()
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(!appState.isPiRunning || appState.isGenerating)
            }
        }
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
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.orange)
                Text(request.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(request.method.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.orange)
            }

            if !request.message.isEmpty {
                Text(request.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch request.method {
            case "confirm":
                HStack(spacing: 8) {
                    Button("Cancel") {
                        appState.respondToUIRequest(confirmed: false)
                    }
                    .buttonStyle(.bordered)
                    Button("Confirm") {
                        appState.respondToUIRequest(confirmed: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.orange)
                }
            case "select":
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(request.options.enumerated()), id: \.offset) { _, option in
                        Button(option) {
                            appState.respondToUIRequest(value: option)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            case "input", "editor":
                if request.method == "editor" {
                    TextEditor(text: $inputText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .frame(minHeight: 90)
                        .padding(6)
                        .background(.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line, lineWidth: 1))
                } else {
                    TextField(request.placeholder, text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line, lineWidth: 1))
                }
                HStack(spacing: 8) {
                    Button("Cancel") {
                        appState.respondToUIRequest(cancelled: true)
                    }
                    .buttonStyle(.bordered)
                    Button("Submit") {
                        appState.respondToUIRequest(value: inputText)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
            default:
                Button("Dismiss") {
                    appState.respondToUIRequest(cancelled: true)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Theme.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.orange.opacity(0.22), lineWidth: 1))
    }
}

struct ActivityTimeline: View {
    let activities: [PiActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Agent activity", systemImage: "bolt.horizontal.circle.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(activities.count) tool\(activities.count == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }

            ForEach(activities) { activity in
                ActivityRow(activity: activity)
            }
        }
        .padding(14)
        .background(Theme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.accent.opacity(0.12), lineWidth: 1))
    }
}

struct ActivityRow: View {
    let activity: PiActivity

    private var icon: String {
        switch activity.state {
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch activity.state {
        case .running: Theme.orange
        case .completed: .green
        case .failed: .red
        }
    }

    private var stateLabel: String {
        switch activity.state {
        case .running: "Running"
        case .completed: "Done"
        case .failed: "Failed"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(activity.toolName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                    Text(stateLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                }
                if !activity.detail.isEmpty {
                    Text(activity.detail)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct ChatMessageBubble: View {
    let message: PiChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: message.isUser ? "person.fill" : "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(message.isUser ? Theme.orange : Theme.accent)
                .frame(width: 26, height: 26)
                .background((message.isUser ? Theme.orange : Theme.accent).opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(message.isUser ? "You" : "Pi")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.muted)
                Text(message.text.isEmpty && message.isStreaming ? "…" : message.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(message.isUser ? Theme.canvas : Theme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AccountUsageCard: View {
    @ObservedObject var usageStore: AccountUsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Accounts & usage")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("Provider balance, authentication, and current session usage")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("Updated \(usageStore.lastUpdated)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Button {
                    usageStore.refresh()
                } label: {
                    Image(systemName: usageStore.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(usageStore.isRefreshing)
            }

            HStack(spacing: 12) {
                ForEach(usageStore.accounts) { account in
                    UsageAccountRow(account: account)
                }
            }

            SessionUsageStrip(usage: usageStore.sessionUsage)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct UsageAccountRow: View {
    let account: AccountUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: account.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(account.tint)
                    .frame(width: 28, height: 28)
                    .background(account.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text(account.authLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                UsageStatePill(state: account.state)
            }

            Text(account.headline)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)

            if let progress = account.progress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(account.tint)
                    if let secondaryProgress = account.secondaryProgress {
                        ProgressView(value: secondaryProgress)
                            .tint(account.tint.opacity(0.45))
                    }
                }
            } else {
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 5)
                    .clipShape(Capsule())
            }

            Text(account.detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(Theme.canvas.opacity(0.62), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct UsageStatePill: View {
    let state: AccountUsageState

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state == .live ? .green : state == .configured ? .orange : .red)
                .frame(width: 6, height: 6)
            Text(state.label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.white, in: Capsule())
    }
}

struct SessionUsageStrip: View {
    let usage: SessionUsage

    var body: some View {
        HStack(spacing: 16) {
            Label("Current Pi session", systemImage: "waveform.path.ecg")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.muted)
            Spacer()
            UsageMetric(label: "Tokens", value: formatCount(usage.totalTokens))
            UsageMetric(label: "Cost", value: String(format: "$%.4f", usage.cost))
            UsageMetric(label: "Context", value: usage.contextPercent.map { String(format: "%.0f%%", $0) } ?? "—")
        }
        .padding(.top, 3)
    }

    private func formatCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

struct UsageMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.ink)
        }
    }
}

struct HeroCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(
                    appState.workspaceScope == .global ? "GLOBAL CHAT" : "CURRENT PROJECT",
                    systemImage: "circle.dotted"
                )
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundStyle(.white.opacity(0.75))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What are you\nworking on?")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Pi is ready to explore, build,\nand organize your next idea.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            HStack(spacing: 10) {
                TextField("Ask Pi anything...", text: $appState.composerText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .onSubmit { appState.sendPrompt() }

                Button {
                    appState.sendPrompt()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 42, height: 42)
                        .background(.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.18), radius: 20, y: 10)
    }
}

struct FocusCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("TODAY'S FOCUS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Image(systemName: "target")
                    .foregroundStyle(Theme.orange)
            }

            Text("Build the foundation\nfor your personal agent")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text("The first step is a small, reliable loop: choose a project, ask Pi, inspect the result.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack(spacing: 8) {
                ProgressView(value: 0.32)
                    .tint(Theme.orange)
                Text("32%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.orange)
            }
        }
        .padding(22)
        .frame(width: 280, height: 250, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct SessionCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let time: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer()
                Text(time)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct QuickAction: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct PlaceholderView: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 130)
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 70, height: 70)
                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 520)
        .padding(34)
    }
}

enum Theme {
    static let sidebar = Color(red: 0.075, green: 0.094, blue: 0.15)
    static let sidebarSecondary = Color(red: 0.59, green: 0.64, blue: 0.73)
    static let canvas = Color(red: 0.965, green: 0.969, blue: 0.98)
    static let ink = Color(red: 0.10, green: 0.12, blue: 0.18)
    static let muted = Color(red: 0.40, green: 0.44, blue: 0.52)
    static let line = Color(red: 0.89, green: 0.90, blue: 0.93)
    static let accent = Color(red: 0.34, green: 0.30, blue: 0.83)
    static let orange = Color(red: 0.94, green: 0.47, blue: 0.20)

    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.47, green: 0.36, blue: 0.93), Color(red: 0.28, green: 0.24, blue: 0.73)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.28, green: 0.23, blue: 0.73), Color(red: 0.40, green: 0.27, blue: 0.78)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
