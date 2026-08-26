import Foundation

enum PiWorkspaceScope: String, CaseIterable, Identifiable, Sendable {
    case workspace
    case global

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: "Project"
        case .global: "Global Chat"
        }
    }

    var icon: String {
        switch self {
        case .workspace: "folder.fill"
        case .global: "globe"
        }
    }
}

struct PiGitStatus: Sendable, Hashable {
    let isRepository: Bool
    let branch: String?
    let changedFiles: Int
    let stagedFiles: Int
    let untrackedFiles: Int

    var isClean: Bool {
        isRepository && changedFiles == 0
    }

    var summary: String {
        guard isRepository else { return "Not a Git repository" }
        if isClean { return "Clean" }
        return "\(changedFiles) changed"
    }
}

struct PiWorkspace: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let path: String
    let repoRoot: String?
    let git: PiGitStatus
    let hasAgentsFile: Bool
    let hasPiDirectory: Bool
    let hasPiSettings: Bool
    var sessionCount: Int
    var projectCount: Int

    var branchLabel: String {
        git.branch ?? "No branch"
    }

    var configurationSummary: String {
        if hasPiSettings { return ".pi/settings.json" }
        if hasPiDirectory { return ".pi/" }
        if hasAgentsFile { return "AGENTS.md" }
        return "No project config"
    }
}

enum PiWorkspaceInspector {
    static func placeholder(path: String) -> PiWorkspace {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let fileManager = FileManager.default
        let piDirectory = url.appendingPathComponent(".pi", isDirectory: true)
        return PiWorkspace(
            id: url.path,
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            path: url.path,
            repoRoot: nil,
            git: PiGitStatus(isRepository: false, branch: nil, changedFiles: 0, stagedFiles: 0, untrackedFiles: 0),
            hasAgentsFile: fileManager.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path),
            hasPiDirectory: fileManager.fileExists(atPath: piDirectory.path),
            hasPiSettings: fileManager.fileExists(atPath: piDirectory.appendingPathComponent("settings.json").path),
            sessionCount: 0,
            projectCount: 0
        )
    }

    static func inspect(path: String, sessions: [PiSavedSession] = []) -> PiWorkspace {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let fileManager = FileManager.default
        let hasAgentsFile = fileManager.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path)
        let piDirectory = url.appendingPathComponent(".pi", isDirectory: true)
        let hasPiDirectory = fileManager.fileExists(atPath: piDirectory.path)
        let hasPiSettings = fileManager.fileExists(atPath: piDirectory.appendingPathComponent("settings.json").path)
        let git = inspectGit(at: url)
        let workspaceSessions = sessions.filter { isInside($0.cwd, root: url.path) }
        let projectCount = Set(workspaceSessions.map(\.cwd)).count

        return PiWorkspace(
            id: url.path,
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            path: url.path,
            repoRoot: git.isRepository ? (runGit(["rev-parse", "--show-toplevel"], at: url)?.trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
            git: git,
            hasAgentsFile: hasAgentsFile,
            hasPiDirectory: hasPiDirectory,
            hasPiSettings: hasPiSettings,
            sessionCount: workspaceSessions.count,
            projectCount: projectCount
        )
    }

    static func isInside(_ path: String, root: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        return normalizedPath == normalizedRoot || normalizedPath.hasPrefix(normalizedRoot + "/")
    }

    private static func inspectGit(at url: URL) -> PiGitStatus {
        guard let statusOutput = runGit(["status", "--porcelain=v1", "-b"], at: url) else {
            return PiGitStatus(isRepository: false, branch: nil, changedFiles: 0, stagedFiles: 0, untrackedFiles: 0)
        }

        let lines = statusOutput.split(whereSeparator: \.isNewline)
        let branchLine = lines.first(where: { $0.hasPrefix("##") })
        let branch = branchLine.map { line in
            let value = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("No commits yet on ") {
                return String(value.dropFirst("No commits yet on ".count))
            }
            return value.split(separator: "...", maxSplits: 1).first.map(String.init) ?? value
        }
        let fileLines = lines.filter { !$0.hasPrefix("##") }
        let stagedFiles = fileLines.filter { line in
            guard line.count >= 2 else { return false }
            return line.first != " " && line.first != "?"
        }.count
        let untrackedFiles = fileLines.filter { $0.hasPrefix("??") }.count

        return PiGitStatus(
            isRepository: true,
            branch: branch,
            changedFiles: fileLines.count,
            stagedFiles: stagedFiles,
            untrackedFiles: untrackedFiles
        )
    }

    private static func runGit(_ arguments: [String], at url: URL) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = url
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
