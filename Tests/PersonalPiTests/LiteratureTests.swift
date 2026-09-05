import Foundation
import Testing
@testable import PersonalPi

@Suite("Literature workflow")
@MainActor
struct LiteratureTests {
    private func event(cwd: String, query: String = "T cell", requestID: String? = nil) throws -> LiteratureEvent {
        var plan: [String: Any] = ["question": "Question", "query": query, "limit": 20, "effectiveQuery": query, "explanation": "Terms"]
        if let requestID { plan["requestId"] = requestID }
        return try #require(LiteratureEvent.decode(["schemaVersion": 1, "kind": "plan", "cwd": cwd, "result": plan]))
    }

    @Test("Plugin is bundled once and Literature is a localized navigation route")
    func bundled() throws {
        let plugin = try #require(PiLaunchConfiguration.bundledPlugins.first { $0.id == "literature" })
        #expect(PiLaunchConfiguration.arguments(projectTrusted: true).filter { $0 == plugin.rootURL.path }.count == 1)
        #expect(AppSection.literature.title == "Literature")
    }

    @Test("Plan event stays editable without a network request and rejects wrong-project data")
    func plans() throws {
        let store = LiteratureStore(piRoot: URL(fileURLWithPath: "/tmp/pi"), executor: { _, _ in Issue.record("Unexpected execution") })
        store.configure(cwd: "/tmp/A")
        store.accept(try event(cwd: "/tmp/A"))
        #expect(store.query == "T cell")
        store.accept(try event(cwd: "/tmp/B", query: "wrong"))
        #expect(store.query == "T cell")
        store.yearFrom = "2020"; store.yearTo = "2025"
        #expect(store.effectiveQuery == "(T cell) AND FIRST_PDATE:[2020-01-01 TO 2025-12-31]")
        store.configure(cwd: "/tmp/B")
        #expect(store.query.isEmpty)
        #expect(store.search == nil && store.saved.isEmpty)
    }

    @Test("A late GUI-requested plan cannot overwrite edited conditions")
    func stalePlan() throws {
        let store = LiteratureStore(piRoot: URL(fileURLWithPath: "/tmp/pi"))
        store.configure(cwd: "/tmp/A")
        let id = store.beginPlanRequest()
        store.query = "User edit"
        store.accept(try event(cwd: "/tmp/A", requestID: id))
        #expect(store.query == "User edit")
    }

    @Test("Delayed search responses cannot cross project changes or query edits")
    func delayed() async throws {
        let pending = LiteraturePending()
        let store = LiteratureStore(piRoot: URL(fileURLWithPath: "/tmp/pi"), executor: { request, done in pending.append(request, done) })
        store.configure(cwd: "/tmp/A"); store.query = "First"; store.runSearch()
        #expect(store.isSearching)
        store.configure(cwd: "/tmp/B"); store.query = "Second"; store.runSearch()
        pending.complete(0, data: Data("{\"success\":false,\"error\":\"old failure\"}".utf8))
        try await Task.sleep(for: .milliseconds(40))
        #expect(store.isSearching && store.error.isEmpty)
        store.query = "Edited"
        pending.complete(1, data: Data("{\"success\":false,\"error\":\"stale failure\"}".utf8))
        try await Task.sleep(for: .milliseconds(40))
        #expect(store.error.isEmpty && !store.isSearching)
        #expect(pending.requests.map(\.cwd).map { URL(fileURLWithPath: $0).lastPathComponent } == ["A", "B"])
    }

    @Test("Invalid years do not issue network work")
    func years() {
        let store = LiteratureStore(piRoot: URL(fileURLWithPath: "/tmp/pi"), executor: { _, _ in Issue.record("Unexpected execution") })
        store.configure(cwd: "/tmp/A"); store.query = "T cell"; store.yearFrom = "xx"
        store.runSearch()
        #expect(store.error == "Year must contain four digits")
    }

    @Test("The actual Swift adapter executes a typed plan without network or a model")
    func nativeBridge() async throws {
        guard ProcessInfo.processInfo.environment["PERSONAL_PI_TEST_KNOWLEDGE_RUNTIME"] == "1" else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LiteratureSwift-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var request = LiteratureRequest(action: "plan", piRoot: root.path, cwd: root.path)
        request.query = "CD4 AND T cell"; request.limit = 20
        let response: Data = try await withCheckedThrowingContinuation { continuation in
            KnowledgeCoreClient.executeLiterature(request: request) { continuation.resume(with: $0) }
        }
        let event = try KnowledgeCoreClient.decode(LiteratureEvent.self, from: response)
        #expect(event.plan?.query == "CD4 AND T cell")
        #expect(event.search == nil)
    }
}

private final class LiteraturePending: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(LiteratureRequest, @Sendable (Result<Data, Error>) -> Void)] = []
    var requests: [LiteratureRequest] { lock.lock(); defer { lock.unlock() }; return values.map(\.0) }
    func append(_ request: LiteratureRequest, _ callback: @escaping @Sendable (Result<Data, Error>) -> Void) {
        lock.lock(); defer { lock.unlock() }; values.append((request, callback))
    }
    func complete(_ index: Int, data: Data) {
        lock.lock(); let callback = values[index].1; lock.unlock()
        callback(.success(data))
    }
}
