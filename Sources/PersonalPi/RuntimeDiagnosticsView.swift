import Foundation
import SwiftUI

enum RuntimeDiagnosticLevel: String, Sendable {
    case ok
    case info
    case warning
    case error

    var label: String {
        switch self {
        case .ok: "OK"
        case .info: "INFO"
        case .warning: "CHECK"
        case .error: "ERROR"
        }
    }

    var color: Color {
        switch self {
        case .ok: Theme.positive
        case .info: Theme.accent
        case .warning: Theme.warning
        case .error: Theme.danger
        }
    }
}

struct RuntimeDiagnosticItem: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let level: RuntimeDiagnosticLevel
}

struct RuntimeDiagnosticSection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [RuntimeDiagnosticItem]
}

struct RuntimeDiagnosticsSnapshot: Sendable {
    let generatedAt: Date
    let sections: [RuntimeDiagnosticSection]

    static let empty = RuntimeDiagnosticsSnapshot(generatedAt: .distantPast, sections: [])
}

struct RuntimeDiagnosticsInput: Sendable {
    let piRoot: String
    let scopePath: String
    let isProject: Bool
    let connectionLabel: String
    let rpcProcessIdentifier: Int32?
}

enum RuntimeDiagnosticsInspector {
    static func inspect(_ input: RuntimeDiagnosticsInput) -> RuntimeDiagnosticsSnapshot {
        let fileManager = FileManager.default
        let piExecutable = PiLaunchConfiguration.resolvedExecutable()
        let nodeExecutable = PiLaunchConfiguration.resolvedNodeExecutable()
        let uvExecutable = PiLaunchConfiguration.resolvedUvExecutable()

        let runtime = RuntimeDiagnosticSection(
            id: "runtime",
            title: "Runtime",
            items: [
                executableItem(
                    id: "pi-cli",
                    title: "Pi CLI",
                    executable: piExecutable,
                    versionArguments: ["--version"]
                ),
                executableItem(
                    id: "node",
                    title: "Node.js",
                    executable: nodeExecutable,
                    versionArguments: ["--version"]
                ),
                executableItem(
                    id: "uv",
                    title: "uv",
                    executable: uvExecutable,
                    versionArguments: ["--version"],
                    missingDetail: "Install uv, set PERSONAL_PI_UV_EXECUTABLE, or configure a Scientific Figure Python override.",
                    missingLevel: .warning
                ),
                RuntimeDiagnosticItem(
                    id: "scientific-figure-runtime",
                    title: "Scientific figure runtime",
                    value: PiLaunchConfiguration.scientificFigureResourceURL == nil ? "Missing" : "Bundled",
                    detail: PiLaunchConfiguration.scientificFigureResourceURL
                        .map { PiFormat.path($0.path) }
                        ?? "The extension, skill, Python runner or lock file is incomplete.",
                    level: PiLaunchConfiguration.scientificFigureResourceURL == nil ? .error : .ok
                ),
                RuntimeDiagnosticItem(
                    id: "rpc",
                    title: "Pi RPC",
                    value: input.connectionLabel,
                    detail: input.rpcProcessIdentifier.map { "Process \($0) · JSONL over stdin/stdout" }
                        ?? "No active child process · JSONL over stdin/stdout",
                    level: input.rpcProcessIdentifier == nil ? .info : .ok
                )
            ]
        )

        let agentRoot = URL(fileURLWithPath: input.piRoot)
            .appendingPathComponent("agent", isDirectory: true)
        let sessionsRoot = agentRoot.appendingPathComponent("sessions", isDirectory: true)
        let global = RuntimeDiagnosticSection(
            id: "global",
            title: "Global Pi",
            items: [
                pathItem(
                    id: "pi-home",
                    title: "Pi home",
                    path: input.piRoot,
                    expectedKind: .directory,
                    fileManager: fileManager
                ),
                presenceItem(
                    id: "global-settings",
                    title: "Global settings",
                    path: agentRoot.appendingPathComponent("settings.json").path,
                    detail: "Configuration only; project settings override matching keys.",
                    fileManager: fileManager
                ),
                presenceItem(
                    id: "auth",
                    title: "Authentication store",
                    path: agentRoot.appendingPathComponent("auth.json").path,
                    detail: "Presence only. Diagnostics never reads or displays credentials.",
                    fileManager: fileManager
                ),
                RuntimeDiagnosticItem(
                    id: "sessions",
                    title: "Saved sessions",
                    value: "\(jsonlCount(at: sessionsRoot, fileManager: fileManager)) JSONL",
                    detail: PiFormat.path(sessionsRoot.path),
                    level: fileManager.fileExists(atPath: sessionsRoot.path) ? .ok : .warning
                )
            ]
        )

        let scopeURL = URL(fileURLWithPath: input.scopePath)
        let projectPi = scopeURL.appendingPathComponent(".pi", isDirectory: true)
        let projectItems: [RuntimeDiagnosticItem]
        if input.isProject {
            projectItems = [
                pathItem(
                    id: "project-root",
                    title: "Project root",
                    path: scopeURL.path,
                    expectedKind: .directory,
                    fileManager: fileManager
                ),
                presenceItem(
                    id: "project-settings",
                    title: "Project settings",
                    path: projectPi.appendingPathComponent("settings.json").path,
                    detail: "Optional .pi/settings.json; loaded because GUI launches Pi with --approve.",
                    missingIsError: false,
                    fileManager: fileManager
                ),
                resourceItem(
                    id: "project-resources",
                    title: "Project resources",
                    root: projectPi,
                    fileManager: fileManager
                ),
                presenceItem(
                    id: "agents",
                    title: "Project context",
                    path: scopeURL.appendingPathComponent("AGENTS.md").path,
                    detail: "AGENTS.md is context; it is independent of project .pi resources.",
                    missingIsError: false,
                    fileManager: fileManager
                )
            ]
        } else {
            projectItems = [
                pathItem(
                    id: "global-chat",
                    title: "Global Chat directory",
                    path: scopeURL.path,
                    expectedKind: .directory,
                    fileManager: fileManager
                ),
                RuntimeDiagnosticItem(
                    id: "project-not-selected",
                    title: "Project resources",
                    value: "Not loaded",
                    detail: "Global Chat does not load any project-level .pi directory.",
                    level: .info
                )
            ]
        }

        return RuntimeDiagnosticsSnapshot(
            generatedAt: Date(),
            sections: [runtime, global, RuntimeDiagnosticSection(id: "scope", title: "Current Scope", items: projectItems)]
        )
    }

    private enum ExpectedPathKind {
        case file
        case directory
    }

    private static func executableItem(
        id: String,
        title: String,
        executable: String?,
        versionArguments: [String],
        missingDetail: String = "Check the runtime installation or set the Personal Pi executable override.",
        missingLevel: RuntimeDiagnosticLevel = .error
    ) -> RuntimeDiagnosticItem {
        guard let executable else {
            return RuntimeDiagnosticItem(
                id: id,
                title: title,
                value: "Not found",
                detail: missingDetail,
                level: missingLevel
            )
        }
        let version = commandOutput(executable: executable, arguments: versionArguments) ?? "Version unavailable"
        return RuntimeDiagnosticItem(
            id: id,
            title: title,
            value: version,
            detail: PiFormat.path(executable),
            level: .ok
        )
    }

    private static func pathItem(
        id: String,
        title: String,
        path: String,
        expectedKind: ExpectedPathKind,
        fileManager: FileManager
    ) -> RuntimeDiagnosticItem {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        let kindMatches = exists && (expectedKind == .directory ? isDirectory.boolValue : !isDirectory.boolValue)
        let writable = exists && fileManager.isWritableFile(atPath: path)
        return RuntimeDiagnosticItem(
            id: id,
            title: title,
            value: kindMatches ? (writable ? "Available · writable" : "Available · read-only") : "Missing",
            detail: PiFormat.path(path),
            level: kindMatches ? (writable ? .ok : .warning) : .error
        )
    }

    private static func presenceItem(
        id: String,
        title: String,
        path: String,
        detail: String,
        missingIsError: Bool = true,
        fileManager: FileManager
    ) -> RuntimeDiagnosticItem {
        let exists = fileManager.fileExists(atPath: path)
        return RuntimeDiagnosticItem(
            id: id,
            title: title,
            value: exists ? "Present" : "Not configured",
            detail: "\(PiFormat.path(path)) · \(detail)",
            level: exists ? .ok : (missingIsError ? .warning : .info)
        )
    }

    private static func resourceItem(
        id: String,
        title: String,
        root: URL,
        fileManager: FileManager
    ) -> RuntimeDiagnosticItem {
        let names = ["extensions", "skills", "prompts", "themes", "knowledge"]
        let present = names.filter {
            fileManager.fileExists(atPath: root.appendingPathComponent($0, isDirectory: true).path)
        }
        return RuntimeDiagnosticItem(
            id: id,
            title: title,
            value: present.isEmpty ? "None configured" : present.joined(separator: ", "),
            detail: PiFormat.path(root.path),
            level: present.isEmpty ? .info : .ok
        )
    }

    private static func jsonlCount(at root: URL, fileManager: FileManager) -> Int {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else { return 0 }
        var count = 0
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            count += 1
        }
        return count
    }

    private static func commandOutput(executable: String, arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = PiLaunchConfiguration.processEnvironment()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct RuntimeDiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var snapshot = RuntimeDiagnosticsSnapshot.empty
    @State private var isRefreshing = false
    @State private var activeRefreshID: UUID?

    private var refreshIdentity: String {
        "\(appState.scopePathLabel)|\(appState.isPiRunning)|\(appState.connectionState.label)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runtime Diagnostics")
                        .font(Theme.serif(30))
                        .foregroundStyle(Theme.ink)
                    Text("Read-only checks for Pi, Node, RPC, global storage, and the current scope.")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.faint)
                }
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }

            if snapshot.sections.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Inspecting local runtime…")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.dim)
                }
                .padding(.vertical, 18)
            } else {
                ForEach(snapshot.sections) { section in
                    DiagnosticSectionView(section: section)
                }
                Text("Last checked \(PiFormat.relative(snapshot.generatedAt)) · no credential contents are read")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.pale)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: 980, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: refreshIdentity) {
            await reload()
        }
    }

    @MainActor
    private func reload() async {
        let refreshID = UUID()
        activeRefreshID = refreshID
        isRefreshing = true
        let input = RuntimeDiagnosticsInput(
            piRoot: appState.piRootDirectory,
            scopePath: appState.scopePathLabel,
            isProject: appState.workspaceScope == .workspace,
            connectionLabel: appState.connectionState.label,
            rpcProcessIdentifier: appState.piClient.processIdentifier
        )
        let inspected = await Task.detached(priority: .utility) {
            RuntimeDiagnosticsInspector.inspect(input)
        }.value
        guard activeRefreshID == refreshID else { return }
        snapshot = inspected
        isRefreshing = false
    }
}

struct DiagnosticSectionView: View {
    let section: RuntimeDiagnosticSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel(text: section.title, size: 9.5)
                .padding(.bottom, 8)
            ForEach(section.items) { item in
                HStack(alignment: .top, spacing: 16) {
                    Circle()
                        .fill(item.level.color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 9) {
                            Text(LocalizedStringKey(item.title))
                                .font(Theme.sans(13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text(LocalizedStringKey(item.level.label))
                                .font(Theme.mono(8.5, weight: .medium))
                                .foregroundStyle(item.level.color)
                        }
                        Text(item.detail)
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.dim)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 16)
                    Text(item.value)
                        .font(Theme.mono(11))
                        .foregroundStyle(item.level == .error ? Theme.danger : Theme.secondary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .overlay(alignment: .top) { Hairline(color: Theme.rule) }
            }
        }
        .padding(.top, 2)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
