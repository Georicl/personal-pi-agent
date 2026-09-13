import Combine
import Foundation

struct LiteraturePlan: Codable, Equatable, Sendable {
    var question: String
    var query: String
    var yearFrom: Int?
    var yearTo: Int?
    var limit: Int
    var effectiveQuery: String
    var explanation: String
    var requestId: String? = nil
}

struct LiteratureProvenance: Codable, Equatable, Sendable {
    let provider: String
    let source: String
    let recordId: String
    let url: String
    let retrievedAt: String
    let query: String
}

struct LiteratureRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let identifiers: [String]
    let title: String
    let authors: [String]
    let year: String
    let doi: String
    let pmid: String
    let pmcid: String
    let abstract: String
    let sourceURL: String
    let originalURL: String
    let fullTextURLs: [String]
    let provenance: [LiteratureProvenance]
}

struct LiteratureSearch: Codable, Sendable {
    let runId: String
    let cwd: String
    let scopeId: String
    let provider: String
    let retrievedAt: String
    let plan: LiteraturePlan
    let totalHits: Int
    let retrievedCount: Int
    let records: [LiteratureRecord]
}

struct LiteratureSavedSource: Codable, Identifiable, Sendable {
    let recordId: String
    let sourceId: String
    let path: String
    let title: String
    let reused: Bool
    var id: String { sourceId }
}

struct LiteratureSave: Codable, Sendable {
    struct Failure: Codable, Sendable { let recordId: String; let error: String }
    let saved: [LiteratureSavedSource]
    let failures: [Failure]
    let runId: String
}

struct LiteratureDraft: Codable, Sendable { let sourceId: String; let path: String }

struct LiteratureEvent: Decodable, Sendable {
    let cwd: String
    let plan: LiteraturePlan?
    let search: LiteratureSearch?
    let saved: LiteratureSave?
    let draft: LiteratureDraft?

    enum CodingKeys: String, CodingKey { case schemaVersion, kind, cwd, result }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else {
            throw KnowledgeCoreClientError.invalidResponse
        }
        cwd = try values.decode(String.self, forKey: .cwd)
        let kind = try values.decode(String.self, forKey: .kind)
        guard ["plan", "search", "saved", "draft"].contains(kind) else { throw KnowledgeCoreClientError.invalidResponse }
        plan = kind == "plan" ? try values.decode(LiteraturePlan.self, forKey: .result) : nil
        search = kind == "search" ? try values.decode(LiteratureSearch.self, forKey: .result) : nil
        saved = kind == "saved" ? try values.decode(LiteratureSave.self, forKey: .result) : nil
        draft = kind == "draft" ? try values.decode(LiteratureDraft.self, forKey: .result) : nil
    }

    static func decode(_ value: Any?) -> Self? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

struct LiteratureRequest: Encodable, Sendable {
    let action: String
    let piRoot: String
    let cwd: String
    var question: String? = nil
    var query: String? = nil
    var yearFrom: Int? = nil
    var yearTo: Int? = nil
    var limit: Int? = nil
    var runId: String? = nil
    var recordIds: [String]? = nil
}

typealias LiteratureExecutor = @Sendable (LiteratureRequest, @escaping @Sendable (Result<Data, Error>) -> Void) -> Void

@MainActor
final class LiteratureStore: ObservableObject {
    @Published var question = ""
    @Published var query = "" { didSet { if oldValue != query { conditionsEdited() } } }
    @Published var yearFrom = "" { didSet { if oldValue != yearFrom { conditionsEdited() } } }
    @Published var yearTo = "" { didSet { if oldValue != yearTo { conditionsEdited() } } }
    @Published var limit = 20 { didSet { if oldValue != limit { conditionsEdited() } } }
    @Published private(set) var explanation = ""
    @Published private(set) var search: LiteratureSearch?
    @Published private(set) var selected = Set<String>()
    @Published private(set) var saved: [LiteratureSavedSource] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isSaving = false
    @Published private(set) var error = ""
    @Published private(set) var status = ""
    @Published private(set) var cwd = ""
    let piRoot: URL
    private let executor: LiteratureExecutor
    private var generation = UUID()
    private var searchRevision = UUID()
    private var applying = false
    private var pendingPlanID: String?

    init(piRoot: URL, executor: @escaping LiteratureExecutor = { request, completion in
        KnowledgeCoreClient.executeLiterature(request: request, completion: completion)
    }) {
        self.piRoot = piRoot
        self.executor = executor
    }

    var scopeName: String {
        isGlobal ? "Global" : URL(fileURLWithPath: cwd).lastPathComponent
    }
    var isGlobal: Bool { Self.canonical(cwd) == Self.canonical(piRoot.appendingPathComponent("chat").path) }
    var destination: String { (isGlobal ? piRoot.appendingPathComponent("knowledge") : URL(fileURLWithPath: cwd).appendingPathComponent(".pi/knowledge")).appendingPathComponent("sources").path }
    var effectiveQuery: String {
        if yearFrom.isEmpty && yearTo.isEmpty { return query.trimmingCharacters(in: .whitespacesAndNewlines) }
        return "(\(query.trimmingCharacters(in: .whitespacesAndNewlines))) AND FIRST_PDATE:[\(yearFrom.isEmpty ? "1000" : yearFrom)-01-01 TO \(yearTo.isEmpty ? "9999" : yearTo)-12-31]"
    }
    var canSearch: Bool { !cwd.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching && !isSaving }
    var canSave: Bool { search != nil && !selected.isEmpty && !isSaving && !isSearching }

    func configure(cwd: String) {
        let value = Self.canonical(cwd)
        guard self.cwd != value else { return }
        generation = UUID()
        self.cwd = value
        applying = true
        question = ""; query = ""; yearFrom = ""; yearTo = ""; limit = 20
        applying = false
        conditionsEdited()
        isSaving = false
    }

    private func conditionsEdited() {
        guard !applying else { return }
        searchRevision = UUID()
        pendingPlanID = nil
        search = nil; selected = []; saved = []; explanation = ""
        isSearching = false; error = ""; status = ""
    }

    func toggle(_ id: String) {
        guard !isSaving, search?.records.contains(where: { $0.id == id }) == true else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func beginPlanRequest() -> String {
        let id = UUID().uuidString
        pendingPlanID = id
        return id
    }

    func runSearch() {
        guard canSearch else { return }
        for value in [yearFrom, yearTo] where !value.isEmpty {
            guard value.count == 4, let year = Int(value), (1000...9999).contains(year) else {
                error = "Year must contain four digits"; return
            }
        }
        if let start = Int(yearFrom), let end = Int(yearTo), start > end {
            error = "Start year must not exceed end year"; return
        }
        let revision = UUID()
        searchRevision = revision
        isSearching = true; search = nil; selected = []; saved = []; error = ""; status = ""
        var request = LiteratureRequest(action: "search", piRoot: piRoot.path, cwd: cwd)
        request.question = question; request.query = query; request.yearFrom = Int(yearFrom); request.yearTo = Int(yearTo); request.limit = limit
        run(request) { [weak self] result in
            guard let self, self.searchRevision == revision else { return }
            self.isSearching = false
            switch result {
            case .success(let event): self.accept(event)
            case .failure(let failure): self.error = failure.localizedDescription
            }
        }
    }

    func saveSelected(onSaved: @escaping @MainActor () -> Void) {
        guard canSave, let search else { return }
        let revision = searchRevision
        isSaving = true; error = ""
        var request = LiteratureRequest(action: "save", piRoot: piRoot.path, cwd: cwd)
        request.runId = search.runId; request.recordIds = search.records.map(\.id).filter { selected.contains($0) }
        run(request) { [weak self] result in
            guard let self else { return }
            self.isSaving = false
            // Writes complete only in the request's original scope. Do not apply
            // the saved selection to a subsequently edited set of conditions.
            guard self.searchRevision == revision else { onSaved(); return }
            switch result {
            case .success(let event): self.accept(event); onSaved()
            case .failure(let failure): self.error = failure.localizedDescription
            }
        }
    }

    @discardableResult
    func accept(_ event: LiteratureEvent) -> Bool {
        guard Self.canonical(event.cwd) == cwd else { return false }
        if let search = event.search, Self.canonical(search.cwd) != cwd { return false }
        if let id = event.plan?.requestId, id != pendingPlanID { return false }
        if event.plan != nil { pendingPlanID = nil }
        if let plan = event.plan ?? event.search?.plan {
            applying = true
            question = plan.question; query = plan.query; yearFrom = plan.yearFrom.map(String.init) ?? ""
            yearTo = plan.yearTo.map(String.init) ?? ""; limit = plan.limit; explanation = plan.explanation
            applying = false
            searchRevision = UUID(); search = event.search; selected = []; saved = []; error = ""; isSearching = false
            status = event.plan == nil ? "Search complete" : "Review the conditions, then search"
        }
        if let result = event.saved, result.runId == search?.runId {
            saved = result.saved
            status = "Selected sources saved"
            error = result.failures.map { "\($0.recordId): \($0.error)" }.joined(separator: "\n")
        }
        if event.draft != nil { status = "Summary saved as draft" }
        return true
    }

    private func run(_ request: LiteratureRequest, completion: @escaping @MainActor (Result<LiteratureEvent, Error>) -> Void) {
        let ticket = generation
        executor(request) { [weak self] result in
            let decoded = result.flatMap { data in Result { try KnowledgeCoreClient.decode(LiteratureEvent.self, from: data) } }
            Task { @MainActor in
                guard let self, self.generation == ticket else { return }
                completion(decoded)
            }
        }
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
