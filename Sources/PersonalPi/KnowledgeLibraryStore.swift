import AppKit
import Combine
import Foundation

struct KnowledgeDirectorySummary: Sendable, Equatable {
    var fileCount = 0
    var totalBytes: Int64 = 0
    var error: String? = nil

    static func scan(_ root: URL) -> Self {
        guard FileManager.default.fileExists(atPath: root.path) else { return Self() }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var result = Self()
        var enumerationError: String?
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles],
            errorHandler: { _, error in enumerationError = error.localizedDescription; return false }
        ) else { return Self(error: "Unable to read knowledge folder") }
        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values.isRegularFile == true else { continue }
                result.fileCount += 1
                result.totalBytes += Int64(values.fileSize ?? 0)
            } catch { result.error = error.localizedDescription }
        }
        if let enumerationError { result.error = enumerationError }
        return result
    }
}

typealias KnowledgeRequestExecutor = @Sendable (
    KnowledgeCoreRequest, URL, URL,
    @escaping @Sendable (Result<Data, Error>) -> Void
) -> Void

@MainActor
final class KnowledgeLibraryStore: ObservableObject {
    @Published private(set) var scope: KnowledgeLibraryScope = .global
    @Published private(set) var projectRoot: URL?
    @Published private(set) var globalSummary: KnowledgeDirectorySummary?
    @Published private(set) var projectSummary: KnowledgeDirectorySummary?
    @Published private(set) var inventory: KnowledgeInventoryResponse?
    @Published private(set) var results: [KnowledgeSearchHit] = []
    @Published private(set) var document: KnowledgeDocumentResponse?
    @Published private(set) var selectedPath: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published private(set) var isSearching = false
    @Published private(set) var isReading = false
    @Published private(set) var hasSearched = false
    @Published private(set) var status = ""
    @Published private(set) var error = ""
    @Published var query = ""
    @Published var fileFilter = ""
    @Published var category: String? = nil

    let piRoot: URL
    private let executor: KnowledgeRequestExecutor
    private var generation = UUID()
    private var inventoryRequest = UUID()
    private var searchRequest = UUID()
    private var detailRequest = UUID()
    private var summaryRequest = UUID()
    private var hasConfigured = false
    private var hasOpened = false

    init(
        piRoot: URL,
        executor: @escaping KnowledgeRequestExecutor = { request, root, cwd, completion in
            KnowledgeCoreClient.execute(request: request, piRoot: root, workingDirectory: cwd, completion: completion)
        }
    ) {
        self.piRoot = piRoot
        self.executor = executor
    }

    var knowledgeRoot: URL {
        Self.root(scope: scope, piRoot: piRoot, projectRoot: projectRoot)
    }

    var projectName: String { projectRoot?.lastPathComponent ?? "" }
    var visibleFiles: [KnowledgeFileEntry] {
        (inventory?.files ?? []).filter { file in
            (category == nil || file.category == category) &&
                (fileFilter.isEmpty || file.relativePath.localizedCaseInsensitiveContains(fileFilter) ||
                    (file.index?.title.localizedCaseInsensitiveContains(fileFilter) ?? false))
        }
    }
    var selectedFile: KnowledgeFileEntry? {
        inventory?.files.first { $0.relativePath == selectedPath }
    }
    var canPublish: Bool {
        guard let file = selectedFile, let index = file.index,
              let preview = document?.document, preview.id == index.documentId,
              preview.contentHash?.isEmpty == false, !isReading else { return false }
        return ["drafts", "entries"].contains(file.category) && index.status == "draft" &&
            index.stale != true && index.error == nil && !isWorking
    }

    func configure(projectRoot: URL?) {
        let canonical = projectRoot?.standardizedFileURL.resolvingSymlinksInPath()
        guard !hasConfigured || self.projectRoot != canonical else { return }
        hasConfigured = true
        self.projectRoot = canonical
        projectSummary = nil
        scope = canonical == nil ? .global : .project
        invalidate()
        if hasOpened { reload() } else { refreshSummaries() }
    }

    func selectScope(_ value: KnowledgeLibraryScope) {
        guard value != scope, value != .project || projectRoot != nil else { return }
        scope = value
        invalidate()
        reload()
    }

    private func invalidate() {
        generation = UUID()
        inventory = nil
        results = []
        document = nil
        selectedPath = nil
        query = ""
        fileFilter = ""
        category = nil
        status = ""
        error = ""
        hasSearched = false
        isLoading = false
        isWorking = false
        isSearching = false
        isReading = false
    }

    func refreshSummaries() {
        let ticket = UUID()
        summaryRequest = ticket
        let root = piRoot.appendingPathComponent("knowledge", isDirectory: true)
        let project = projectRoot?.appendingPathComponent(".pi/knowledge", isDirectory: true)
        Task {
            let values = await Task.detached(priority: .utility) {
                (KnowledgeDirectorySummary.scan(root), project.map(KnowledgeDirectorySummary.scan))
            }.value
            guard self.summaryRequest == ticket else { return }
            self.globalSummary = values.0
            self.projectSummary = values.1
        }
    }

    func reload() {
        hasOpened = true
        let ticket = UUID()
        inventoryRequest = ticket
        isLoading = true
        error = ""
        refreshSummaries()
        run(request("inventory", limit: 5_000)) { [weak self] (result: Result<KnowledgeInventoryResponse, Error>) in
            guard let self, self.inventoryRequest == ticket else { return }
            self.isLoading = false
            switch result {
            case .success(let snapshot):
                self.inventory = snapshot
                if !snapshot.files.contains(where: { $0.relativePath == self.selectedPath }) {
                    self.selectFile(nil)
                }
            case .failure(let failure): self.error = failure.localizedDescription
            }
        }
    }

    func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { clearSearch(); return }
        let ticket = UUID()
        searchRequest = ticket
        isSearching = true
        hasSearched = true
        results = []
        error = ""
        run(request("search", query: text, limit: 50)) { [weak self] (result: Result<KnowledgeSearchResponse, Error>) in
            guard let self, self.searchRequest == ticket else { return }
            self.isSearching = false
            switch result {
            case .success(let response):
                self.results = response.results
                if let unavailable = response.scopes.first(where: { !$0.initialized }) {
                    self.error = unavailable.error ?? "Index knowledge before searching"
                }
            case .failure(let failure): self.error = failure.localizedDescription
            }
        }
    }

    func clearSearch() {
        searchRequest = UUID()
        results = []
        hasSearched = false
        isSearching = false
        query = ""
        error = ""
    }

    func selectFile(_ path: String?) {
        detailRequest = UUID()
        let ticket = detailRequest
        selectedPath = path
        document = nil
        isReading = false
        guard let index = selectedFile?.index, index.error == nil else { return }
        isReading = true
        var payload = request("get")
        payload.documentId = index.documentId
        run(payload) { [weak self] (result: Result<KnowledgeDocumentResponse, Error>) in
            guard let self, self.detailRequest == ticket else { return }
            self.isReading = false
            switch result {
            case .success(let value): self.document = value
            case .failure(let failure): self.error = failure.localizedDescription
            }
        }
    }

    func index(rebuild: Bool = false) {
        guard !isWorking else { return }
        beginWork("Updating knowledge index…")
        run(request(rebuild ? "rebuild" : "index")) { [weak self] (result: Result<KnowledgeIndexResponse, Error>) in
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let response):
                self.status = "Knowledge index updated"
                self.reload()
                self.error = response.failures.map { "\($0.path): \($0.error)" }.joined(separator: "\n")
            case .failure(let failure): self.error = failure.localizedDescription
            }
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !isWorking, !urls.isEmpty else { return }
        beginWork("Importing knowledge files…")
        var payload = request("import")
        payload.paths = urls.map(\.path)
        run(payload) { [weak self] (result: Result<KnowledgeImportResponse, Error>) in
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let response):
                self.status = "Knowledge import completed"
                self.reload()
                self.error = (response.failures + (response.index?.failures ?? []))
                    .map { "\($0.path): \($0.error)" }.joined(separator: "\n")
            case .failure(let failure): self.error = failure.localizedDescription
            }
        }
    }

    func publishSelectedCard() {
        guard canPublish, let id = selectedFile?.index?.documentId,
              let confirmedHash = document?.document.contentHash else { return }
        beginWork("Publishing knowledge card…")
        var payload = request("publish")
        payload.documentId = id
        payload.userConfirmed = true // Called by the user's explicit publish button.
        payload.expectedContentHash = confirmedHash
        run(payload) { [weak self] (result: Result<KnowledgeDocumentResponse, Error>) in
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let response):
                self.status = response.recoveryPath.map { "Knowledge card published · Original retained at \($0)" }
                    ?? "Knowledge card published"
                self.selectFile(nil)
                self.reload()
            case .failure(let failure): self.error = failure.localizedDescription
            }
        }
    }

    func knowledgeChanged() {
        if hasOpened { clearSearch(); reload() } else { refreshSummaries() }
    }

    private func beginWork(_ message: String) {
        isWorking = true
        error = ""
        status = message
        clearSearch()
        selectFile(nil)
    }

    func fileURL(_ relativePath: String) -> URL? {
        let root = knowledgeRoot.resolvingSymlinksInPath()
        let file = root.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/") else { return nil }
        return file
    }

    func openFolder() {
        do {
            try FileManager.default.createDirectory(at: knowledgeRoot, withIntermediateDirectories: true)
            NSWorkspace.shared.open(knowledgeRoot)
        } catch { self.error = error.localizedDescription }
    }

    static func root(scope: KnowledgeLibraryScope, piRoot: URL, projectRoot: URL?) -> URL {
        if scope == .project, let projectRoot {
            return projectRoot.appendingPathComponent(".pi/knowledge", isDirectory: true)
        }
        return piRoot.appendingPathComponent("knowledge", isDirectory: true)
    }

    private func request(_ action: String, query: String? = nil, limit: Int? = nil) -> KnowledgeCoreRequest {
        let selected = KnowledgeScopePayload(kind: scope.rawValue, projectRoot: scope == .project ? projectRoot?.path : nil)
        return KnowledgeCoreRequest(
            action: action, piRoot: piRoot.path,
            scope: action == "search" ? nil : selected,
            scopes: action == "search" ? [selected] : nil, query: query, limit: limit
        )
    }

    private func run<Response: Decodable & Sendable>(
        _ request: KnowledgeCoreRequest,
        completion: @escaping @MainActor (Result<Response, Error>) -> Void
    ) {
        let context = generation
        executor(request, piRoot, projectRoot ?? FileManager.default.temporaryDirectory) { [weak self] result in
            let decoded: Result<Response, Error> = result.flatMap { data in
                Result { try KnowledgeCoreClient.decode(Response.self, from: data) }
            }
            Task { @MainActor in
                guard let self, self.generation == context else { return }
                completion(decoded)
            }
        }
    }
}
