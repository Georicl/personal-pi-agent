import SwiftUI

struct KnowledgeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom, spacing: 16) {
                Text("Knowledge")
                    .font(Theme.serif(30))
                    .foregroundStyle(Theme.ink)
                Text("Directories Pi can retrieve from. Nothing here is injected into every prompt.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.faint)
                    .padding(.bottom, 3)
            }

            HStack(alignment: .top, spacing: 16) {
                KnowledgeScopeCard(
                    title: "Global knowledge",
                    kicker: "Shared across Global Chat and every project",
                    path: appState.globalKnowledgeDirectory,
                    fileCount: appState.globalKnowledgeFileCount,
                    isAvailable: true,
                    action: appState.openGlobalKnowledge
                )

                KnowledgeScopeCard(
                    title: "Project knowledge",
                    kicker: appState.workspaceScope == .workspace
                        ? "Private to \(appState.workspace.name)"
                        : "Select a project to use project knowledge",
                    path: appState.workspaceScope == .workspace
                        ? appState.projectKnowledgeDirectory
                        : "No project selected",
                    fileCount: appState.workspaceScope == .workspace
                        ? appState.projectKnowledgeFileCount
                        : 0,
                    isAvailable: appState.workspaceScope == .workspace,
                    action: appState.openProjectKnowledge
                )
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: 980, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KnowledgeScopeCard: View {
    let title: String
    let kicker: String
    let path: String
    let fileCount: Int
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(Theme.sans(13.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(LocalizedStringKey(kicker))
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.faint)
            }

            Text(isAvailable ? PiFormat.path(path) : path)
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.dim)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack {
                Text("\(fileCount) files")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button("Open folder", action: action)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(isAvailable ? Theme.secondary : Theme.pale)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isAvailable ? Color(red: 223 / 255, green: 227 / 255, blue: 232 / 255) : Theme.rule, lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                    .disabled(!isAvailable)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .opacity(isAvailable ? 1 : 0.72)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }
}
