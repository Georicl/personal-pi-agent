import Foundation
import Testing
@testable import PersonalPi

@Suite("Knowledge library")
struct KnowledgeLibraryTests {
    @Test("Inventory decodes timestamps, byte totals and stale index status")
    func decodesInventory() throws {
        let snapshot = try KnowledgeCoreClient.decodeInventory(inventoryFixture(root: "/tmp/pi", count: 7))
        #expect(snapshot.fileCount == 7)
        #expect(snapshot.totalBytes == 2048)
        #expect(snapshot.latestRun?.date != nil)
        #expect(snapshot.files.first?.modifiedDate != nil)
        #expect(snapshot.files.first?.index?.stale == true)
        #expect(KnowledgeCategory.status(try #require(snapshot.files.first)) == "Index needs update")
        let error = Data(#"{"success":false,"error":"index unavailable"}"#.utf8)
        #expect(throws: KnowledgeCoreClientError.self) { try KnowledgeCoreClient.decodeInventory(error) }
    }

    @Test("Sidebar summary includes unclassified files and excludes symlinks and hidden files")
    func summarizesFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sources"), withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: root.appendingPathComponent("sources/paper.txt"))
        try Data("12345".utf8).write(to: root.appendingPathComponent("loose.md"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".private"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.txt"), withDestinationURL: root.appendingPathComponent("sources/paper.txt"))
        let result = KnowledgeDirectorySummary.scan(root)
        #expect(result.fileCount == 2)
        #expect(result.totalBytes == 8)
    }

    @Test("Project switches discard old inventory and late mutation responses")
    @MainActor
    func switchesWithoutStaleResults() async throws {
        let pending = PendingKnowledgeRequests()
        let store = KnowledgeLibraryStore(piRoot: URL(fileURLWithPath: "/tmp/test-pi"), executor: pending.execute)
        store.configure(projectRoot: URL(fileURLWithPath: "/tmp/project-a"))
        store.reload()
        store.index()
        store.configure(projectRoot: URL(fileURLWithPath: "/tmp/project-b"))
        #expect(store.inventory == nil)
        #expect(!store.isWorking)
        #expect(store.projectName == "project-b")
        pending.finish(2, data: inventoryFixture(root: "/tmp/project-b/.pi", count: 2))
        await settle()
        #expect(store.inventory?.fileCount == 2)
        pending.finish(0, data: inventoryFixture(root: "/tmp/project-a/.pi", count: 99))
        pending.fail(1)
        await settle()
        #expect(store.inventory?.fileCount == 2)
        #expect(store.error.isEmpty)
        #expect(!store.isWorking)
    }

    @Test("Only the latest refresh updates the library")
    @MainActor
    func ignoresEarlierRefresh() async {
        let pending = PendingKnowledgeRequests()
        let store = KnowledgeLibraryStore(piRoot: URL(fileURLWithPath: "/tmp/test-pi"), executor: pending.execute)
        store.configure(projectRoot: nil)
        store.reload()
        store.reload()
        pending.finish(1, data: inventoryFixture(root: "/tmp/test-pi", count: 2))
        await settle()
        pending.finish(0, data: inventoryFixture(root: "/tmp/test-pi", count: 1))
        await settle()
        #expect(store.inventory?.fileCount == 2)
        #expect(!store.isLoading)
    }

    @Test("Search surfaces missing indexes and clearing search discards late responses")
    @MainActor
    func searchState() async throws {
        let pending = PendingKnowledgeRequests()
        let store = KnowledgeLibraryStore(piRoot: URL(fileURLWithPath: "/tmp/test-pi"), executor: pending.execute)
        store.configure(projectRoot: nil)
        store.query = "evidence"
        store.search()
        let missing = Data(#"{"success":true,"query":"evidence","results":[],"scopes":[{"scope":{"id":"global","kind":"global","knowledgeRoot":"/tmp/test-pi/knowledge","projectRoot":null,"indexPath":"/tmp/test-pi/index.sqlite"},"initialized":false,"error":"index not initialized"}]}"#.utf8)
        pending.finish(0, data: missing)
        await settle()
        #expect(store.error == "index not initialized")
        store.search()
        store.clearSearch()
        pending.finish(1, data: missing)
        await settle()
        #expect(!store.hasSearched)
        #expect(store.results.isEmpty)
    }

    @Test("The real Swift client can import, index, inventory, search and read a document",
          .enabled(if: ProcessInfo.processInfo.environment["PERSONAL_PI_TEST_KNOWLEDGE_RUNTIME"] == "1"))
    func realRuntimeRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        let piRoot = root.appendingPathComponent("pi")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.md")
        try Data("# Evidence\n\nSwift knowledge bridge preserves provenance.".utf8).write(to: source)
        let scope = KnowledgeScopePayload(kind: "project", projectRoot: project.path)
        func call(_ request: KnowledgeCoreRequest) async throws -> Data {
            try await withCheckedThrowingContinuation { continuation in
                KnowledgeCoreClient.execute(request: request, piRoot: piRoot, workingDirectory: project) {
                    continuation.resume(with: $0)
                }
            }
        }
        var request = KnowledgeCoreRequest(action: "import", piRoot: piRoot.path, scope: scope, scopes: nil, query: nil, limit: nil)
        request.paths = [source.path]
        let imported = try KnowledgeCoreClient.decode(KnowledgeImportResponse.self, from: await call(request))
        #expect(imported.imported == ["sources/source.md"])
        #expect(imported.index?.indexed == 1)
        let snapshot = try KnowledgeCoreClient.decodeInventory(await call(KnowledgeCoreRequest(
            action: "inventory", piRoot: piRoot.path, scope: scope, scopes: nil, query: nil, limit: 500
        )))
        #expect(snapshot.fileCount == 1)
        #expect(snapshot.latestRun?.date != nil)
        let result = try KnowledgeCoreClient.decodeSearch(await call(KnowledgeCoreRequest(
            action: "search", piRoot: piRoot.path, scope: nil, scopes: [scope], query: "preserves provenance", limit: 20
        )))
        #expect(result.results.first?.chunk.locator == "Section: Evidence")
        let id = try #require(snapshot.files.first?.index?.documentId)
        request = KnowledgeCoreRequest(action: "get", piRoot: piRoot.path, scope: scope, scopes: nil, query: nil, limit: nil)
        request.documentId = id
        let document = try KnowledgeCoreClient.decode(KnowledgeDocumentResponse.self, from: await call(request))
        #expect(document.chunks.first?.text.contains("preserves provenance") == true)
    }

    @Test("Publish uses the displayed document version and is unavailable before preview loads")
    @MainActor
    func publishPreviewVersion() async throws {
        let pending = PendingKnowledgeRequests()
        let store = KnowledgeLibraryStore(piRoot: URL(fileURLWithPath: "/tmp/test-pi"), executor: pending.execute)
        store.configure(projectRoot: nil)
        store.reload()
        let draftInventory = String(decoding: inventoryFixture(root: "/tmp/test-pi", count: 1), as: UTF8.self)
            .replacingOccurrences(of: "sources", with: "drafts")
            .replacingOccurrences(of: "\"active\"", with: "\"draft\"")
            .replacingOccurrences(of: "\"stale\":true", with: "\"stale\":false")
        pending.finish(0, data: Data(draftInventory.utf8))
        await settle()
        store.selectFile("drafts/evidence.md")
        #expect(!store.canPublish)
        let preview = Data(#"{"success":true,"document":{"id":"paper-1","relativePath":"drafts/evidence.md","category":"drafts","title":"Evidence","status":"draft","contentHash":"confirmed-version"},"chunks":[]}"#.utf8)
        pending.finish(1, data: preview)
        await settle()
        #expect(store.canPublish)
        store.publishSelectedCard()
        let request = pending.request(2)
        #expect(request.action == "publish")
        #expect(request.documentId == "paper-1")
        #expect(request.expectedContentHash == "confirmed-version")
        #expect(request.userConfirmed == true)
        #expect(!store.canPublish)
        pending.fail(2)
        await settle()
        #expect(!store.error.isEmpty)
    }

    private func inventoryFixture(root: String, count: Int) -> Data {
        Data("""
        {"success":true,"scope":{"id":"global","kind":"global","knowledgeRoot":"\(root)/knowledge","projectRoot":null,"indexPath":"\(root)/index.sqlite"},"initialized":true,"fileCount":\(count),"totalBytes":2048,"categories":{"sources":{"files":1,"bytes":2048}},"files":[{"relativePath":"sources/evidence.md","category":"sources","name":"evidence.md","extension":".md","sizeBytes":2048,"modifiedAt":"2026-09-05T02:03:04.123456Z","supported":true,"index":{"documentId":"paper-1","title":"Evidence","status":"active","chunks":1,"error":null,"stale":true}}],"truncated":false,"latestRun":{"id":"run-1","action":"index","finished_at":"2026-09-05T01:02:03.123456Z"}}
        """.utf8)
    }

    @MainActor private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

private final class PendingKnowledgeRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: [@Sendable (Result<Data, Error>) -> Void] = []
    private var requests: [KnowledgeCoreRequest] = []
    func execute(_ request: KnowledgeCoreRequest, _ root: URL, _ cwd: URL, _ completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        lock.lock()
        callbacks.append(completion)
        requests.append(request)
        lock.unlock()
    }
    func finish(_ index: Int, data: Data) { callback(index)(.success(data)) }
    func request(_ index: Int) -> KnowledgeCoreRequest {
        lock.lock()
        defer { lock.unlock() }
        return requests[index]
    }
    func fail(_ index: Int) { callback(index)(.failure(KnowledgeCoreClientError.operationFailed("old request failed"))) }
    private func callback(_ index: Int) -> @Sendable (Result<Data, Error>) -> Void {
        lock.lock()
        defer { lock.unlock() }
        return callbacks[index]
    }
}
