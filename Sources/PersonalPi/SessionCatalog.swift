import Foundation

enum PiSessionDirectoryResolver {
    static func scanRoots(
        piRoot: URL,
        globalChatDirectory: String,
        projectPaths: [String],
        environmentSessionDirectory: String? = ProcessInfo.processInfo.environment["PI_CODING_AGENT_SESSION_DIR"],
        homeDirectory: String = NSHomeDirectory()
    ) -> [URL] {
        let context = PiRuntimeContext(dataRoot: piRoot)
        let globalSettings = readSettings(at: context.settingsURL)
        let defaultRoot = context.sessionsURL.standardizedFileURL
        var roots = [defaultRoot]

        let workingDirectories = [globalChatDirectory] + projectPaths
        for workingDirectory in workingDirectories {
            let projectSettings = readSettings(
                at: URL(fileURLWithPath: workingDirectory, isDirectory: true)
                    .appendingPathComponent(".pi/settings.json")
            )
            let effectiveSettings = PiSettingsFile.merge(globalSettings, projectSettings)
            let configuredDirectory = environmentSessionDirectory?.nonEmptyValue
                ?? (effectiveSettings["sessionDir"] as? String)?.nonEmptyValue
            guard let configuredDirectory else { continue }
            roots.append(
                resolve(
                    configuredDirectory,
                    relativeTo: workingDirectory,
                    homeDirectory: homeDirectory
                )
            )
        }

        var seen = Set<String>()
        return roots.filter { root in
            seen.insert(canonicalPath(root)).inserted
        }
    }

    static func resolve(
        _ rawPath: String,
        relativeTo workingDirectory: String,
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        let expanded: String
        if rawPath == "~" {
            expanded = homeDirectory
        } else if rawPath.hasPrefix("~/") {
            expanded = (homeDirectory as NSString).appendingPathComponent(String(rawPath.dropFirst(2)))
        } else if rawPath.hasPrefix("file://"), let fileURL = URL(string: rawPath), fileURL.isFileURL {
            return fileURL.standardizedFileURL
        } else {
            expanded = rawPath
        }

        if (expanded as NSString).isAbsolutePath {
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }
        return URL(fileURLWithPath: expanded, isDirectory: true, relativeTo: URL(fileURLWithPath: workingDirectory, isDirectory: true))
            .absoluteURL
            .standardizedFileURL
    }

    private static func readSettings(at url: URL) -> [String: Any] {
        (try? PiSettingsFile.read(url)) ?? [:]
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

enum PiSessionCatalog {
    static func allSessions(at roots: [URL]) -> [PiSavedSession] {
        var sessionsByPath: [String: PiSavedSession] = [:]
        for root in roots {
            for session in allSessions(at: root) {
                let path = URL(fileURLWithPath: session.path)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
                    .path
                sessionsByPath[path] = session
            }
        }
        return sessionsByPath.values.sorted { $0.timestamp > $1.timestamp }
    }

    static func allSessions(at root: URL) -> [PiSavedSession] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [] }

        var sessions: [PiSavedSession] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let header = readHeader(from: url) ?? [:]
            guard header["type"] as? String == "session" else { continue }
            let id = header["id"] as? String ?? url.deletingPathExtension().lastPathComponent
            let cwd = header["cwd"] as? String ?? ""
            let timestampText = header["timestamp"] as? String
            let timestamp = timestampText.flatMap { date(from: $0) }
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? Date.distantPast
            sessions.append(PiSavedSession(id: id, path: url.path, timestamp: timestamp, cwd: cwd))
        }
        return sessions.sorted { $0.timestamp > $1.timestamp }
    }

    static func projectGroups(from sessions: [PiSavedSession]) -> [PiProjectGroup] {
        Dictionary(grouping: sessions, by: \.cwd)
            .map { cwd, sessions in
                PiProjectGroup(
                    id: cwd.isEmpty ? "unknown" : cwd,
                    cwd: cwd,
                    sessions: sessions.sorted { $0.timestamp > $1.timestamp }
                )
            }
            .sorted { lhs, rhs in
                (lhs.latestSession?.timestamp ?? .distantPast) > (rhs.latestSession?.timestamp ?? .distantPast)
            }
    }

    private static func readHeader(from url: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 8192)
        guard let firstLine = String(data: data, encoding: .utf8)?.split(separator: "\n", maxSplits: 1).first,
              let lineData = firstLine.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
    }

    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
