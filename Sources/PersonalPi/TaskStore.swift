import Foundation

enum PiTaskState: String, Codable, CaseIterable, Sendable {
    case submitted
    case running
    case waiting
    case finished

    var title: String {
        switch self {
        case .submitted: "Submitted"
        case .running: "Running"
        case .waiting: "Waiting"
        case .finished: "Finished"
        }
    }

    var icon: String {
        switch self {
        case .submitted: "tray.and.arrow.down.fill"
        case .running: "waveform.path.ecg"
        case .waiting: "pause.circle.fill"
        case .finished: "checkmark.circle.fill"
        }
    }
}

struct PiTaskRecord: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let title: String
    let scopeName: String
    let workingDirectory: String
    let createdAt: Date
    var sessionKey: String?
    var updatedAt: Date
    var state: PiTaskState
    var detail: String
    var hasUnreadUpdate: Bool
}

@MainActor
final class PiTaskStore: ObservableObject {
    @Published private(set) var tasks: [PiTaskRecord] = []

    private let storageURL: URL
    private let persistenceQueue = DispatchQueue(label: "dev.pi.personal.task-store", qos: .utility)

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? PersonalPiRuntimeEnvironment.piRootURL
            .appendingPathComponent("agent/personal-pi-tasks.json")
        load()
    }

    var unreadCount: Int {
        tasks.filter(\.hasUnreadUpdate).count
    }

    func beginOrResume(
        sessionKey: String,
        title: String,
        scopeName: String,
        workingDirectory: String
    ) -> String {
        if let index = tasks.firstIndex(where: { $0.sessionKey == sessionKey }) {
            let task = tasks.remove(at: index)
            tasks.insert(task, at: 0)
            tasks[0].state = .submitted
            tasks[0].detail = "New request submitted"
            tasks[0].updatedAt = Date()
            tasks[0].hasUnreadUpdate = false
            persist()
            return tasks[0].id
        }

        let id = UUID().uuidString
        let now = Date()
        tasks.insert(
            PiTaskRecord(
                id: id,
                title: title,
                scopeName: scopeName,
                workingDirectory: workingDirectory,
                createdAt: now,
                sessionKey: sessionKey,
                updatedAt: now,
                state: .submitted,
                detail: "Submitted to Pi",
                hasUnreadUpdate: false
            ),
            at: 0
        )
        persist()
        return id
    }

    func resume(id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = .submitted
        tasks[index].detail = "New request submitted"
        tasks[index].updatedAt = Date()
        tasks[index].hasUnreadUpdate = false
        persist()
    }

    func taskId(for sessionKey: String) -> String? {
        tasks.first(where: { $0.sessionKey == sessionKey })?.id
    }

    func bind(id: String?, to sessionKey: String) {
        guard let id, let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        guard tasks[index].sessionKey != sessionKey else { return }
        tasks[index].sessionKey = sessionKey
        persist()
    }

    func reconcileSessions(_ sessions: [PiSavedSession]) {
        var changed = false

        for index in tasks.indices where tasks[index].sessionKey == nil {
            let candidates = sessions
                .filter {
                    $0.cwd == tasks[index].workingDirectory &&
                    $0.timestamp <= tasks[index].createdAt
                }
                .sorted { $0.timestamp > $1.timestamp }
            if let session = candidates.first {
                tasks[index].sessionKey = session.id
                changed = true
            }
        }

        let duplicateSessionKeys = Dictionary(grouping: tasks.indices) { tasks[$0].sessionKey }
            .compactMap { key, indices -> (String, [Int])? in
                guard let key, indices.count > 1 else { return nil }
                return (key, indices)
            }

        var idsToRemove = Set<String>()
        for (_, indices) in duplicateSessionKeys {
            let ordered = indices.sorted { tasks[$0].createdAt < tasks[$1].createdAt }
            guard let keeperIndex = ordered.first else { continue }
            let newest = ordered.max { tasks[$0].updatedAt < tasks[$1].updatedAt } ?? keeperIndex
            tasks[keeperIndex].updatedAt = tasks[newest].updatedAt
            tasks[keeperIndex].state = tasks[newest].state
            tasks[keeperIndex].detail = tasks[newest].detail
            tasks[keeperIndex].hasUnreadUpdate = ordered.contains { tasks[$0].hasUnreadUpdate }
            for duplicateIndex in ordered.dropFirst() {
                idsToRemove.insert(tasks[duplicateIndex].id)
            }
            changed = true
        }

        if !idsToRemove.isEmpty {
            tasks.removeAll { idsToRemove.contains($0.id) }
        }
        if changed {
            tasks.sort { $0.updatedAt > $1.updatedAt }
            persist()
        }
    }

    func update(id: String?, state: PiTaskState, detail: String, unread: Bool? = nil) {
        guard let id, let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = state
        tasks[index].detail = detail
        tasks[index].updatedAt = Date()
        if let unread {
            tasks[index].hasUnreadUpdate = unread
        }
        persist()
    }

    func markViewed(_ task: PiTaskRecord) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].hasUnreadUpdate = false
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([PiTaskRecord].self, from: data) else {
            return
        }
        tasks = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        let snapshot = tasks
        let destination = storageURL
        persistenceQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(snapshot).write(to: destination, options: .atomic)
            } catch {
                // Task tracking must never interrupt the active Pi session.
            }
        }
    }
}
