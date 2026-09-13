import SwiftUI

struct LiteratureView: View {
    @ObservedObject var store: LiteratureStore
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Literature").font(Theme.serif(30)).foregroundStyle(Theme.ink)
                .accessibilityIdentifier("literature-heading")
            Text("Review search conditions, choose sources, then draft a cited summary.")
                .font(Theme.sans(12)).foregroundStyle(Theme.faint)
            VStack(alignment: .leading, spacing: 12) {
                TextField("Research question", text: $store.question)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("literature-question")
                HStack {
                    Button("Prepare conditions with Pi") { appState.prepareLiteraturePlan() }
                        .disabled(store.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !appState.canRequestLiteratureAgent || store.isSaving)
                        .accessibilityIdentifier("literature-plan-button")
                    Text("Uses the current session and model; no search until you confirm.")
                        .font(Theme.sans(11)).foregroundStyle(Theme.faint)
                }
                if !appState.canRequestLiteratureAgent {
                    Text("Finish the current request or clear the session composer before asking Pi.")
                        .font(Theme.sans(11)).foregroundStyle(Theme.muted)
                }
            }.padding(16).background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 12) {
                Text("Search conditions").font(Theme.sans(14, weight: .medium))
                Text("Europe PMC · includes PubMed records · metadata and abstracts only")
                    .font(Theme.sans(11)).foregroundStyle(Theme.faint)
                TextField("Europe PMC query (editable)", text: $store.query, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...5)
                    .accessibilityIdentifier("literature-query")
                HStack(spacing: 12) {
                    TextField("From year", text: $store.yearFrom).frame(width: 100)
                        .accessibilityIdentifier("literature-year-from")
                    TextField("To year", text: $store.yearTo).frame(width: 100)
                        .accessibilityIdentifier("literature-year-to")
                    Picker("Result limit", selection: $store.limit) {
                        ForEach([10, 20, 50], id: \.self) { Text("\($0)").tag($0) }
                    }.frame(width: 165)
                    Spacer(minLength: 0)
                }.textFieldStyle(.roundedBorder)
                if !store.explanation.isEmpty {
                    Text(store.explanation).font(Theme.sans(12)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                }
                Text("Exact query sent to Europe PMC").font(Theme.sans(11)).foregroundStyle(Theme.faint)
                Text(verbatim: store.effectiveQuery.isEmpty ? "—" : store.effectiveQuery)
                    .font(Theme.mono(11)).textSelection(.enabled).accessibilityIdentifier("literature-outbound-query")
                HStack {
                    Button("Search literature") { store.runSearch() }
                        .buttonStyle(.borderedProminent).disabled(!store.canSearch)
                        .accessibilityIdentifier("literature-search-button")
                    if store.isSearching { ProgressView().controlSize(.small) }
                    Text("Only these conditions are sent; local knowledge is not uploaded.")
                        .font(Theme.sans(11)).foregroundStyle(Theme.faint)
                }
            }.padding(16).background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))

            if !store.error.isEmpty {
                Text(LocalizedStringKey(store.error)).font(Theme.sans(12)).foregroundStyle(Theme.danger)
                    .textSelection(.enabled).accessibilityIdentifier("literature-error")
            }
            if !store.status.isEmpty {
                Text(LocalizedStringKey(store.status)).font(Theme.sans(12)).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("literature-status")
            }
            if let result = store.search {
                results(result)
            }
        }.padding(32).frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func results(_ result: LiteratureSearch) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(result.records.count) unique / \(result.retrievedCount) retrieved / \(result.totalHits) total hits")
                .font(Theme.mono(12)).accessibilityIdentifier("literature-result-count")
            Text("A limited discovery search, not an exhaustive systematic review.")
                .font(Theme.sans(11)).foregroundStyle(Theme.faint)
            Text("\(result.provider) · \(result.retrievedAt)").font(Theme.mono(10)).foregroundStyle(Theme.faint)
            Text(PiFormat.path(store.destination)).font(Theme.mono(10)).textSelection(.enabled)
                .accessibilityIdentifier("literature-destination")
            HStack {
                Button("Save selected sources") { store.saveSelected { appState.knowledgeStore.knowledgeChanged() } }
                    .disabled(!store.canSave).accessibilityIdentifier("literature-save-button")
                if store.isSaving { ProgressView().controlSize(.small) }
                Button("Summarize saved sources with Pi") { appState.summarizeLiteratureSources() }
                    .disabled(store.saved.isEmpty || !appState.canRequestLiteratureAgent || store.isSaving)
                    .accessibilityIdentifier("literature-summary-button")
            }
            ForEach(result.records) { record in
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(get: { store.selected.contains(record.id) }, set: { _ in store.toggle(record.id) })) {
                        Text(verbatim: record.title).font(Theme.sans(14, weight: .medium))
                    }.toggleStyle(.checkbox).disabled(store.isSaving)
                        .accessibilityIdentifier("literature-record-\(record.id)")
                    Text(verbatim: "\(record.authors.isEmpty ? "—" : record.authors.joined(separator: "; ")) · \(record.year.isEmpty ? "—" : record.year)")
                        .font(Theme.sans(11)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                    Text(verbatim: "DOI: \(record.doi.isEmpty ? "—" : record.doi) · PMID: \(record.pmid.isEmpty ? "—" : record.pmid) · PMCID: \(record.pmcid.isEmpty ? "—" : record.pmcid)")
                        .font(Theme.mono(10)).textSelection(.enabled)
                    DisclosureGroup("Abstract and provenance") {
                        VStack(alignment: .leading, spacing: 8) {
                            if record.abstract.isEmpty {
                                Text("No abstract supplied by provider.")
                            } else { Text(verbatim: record.abstract).textSelection(.enabled) }
                            ForEach(Array(record.provenance.enumerated()), id: \.offset) { _, source in
                                Text(verbatim: "\(source.provider) / \(source.source):\(source.recordId) · \(source.retrievedAt)\n\(source.query)")
                                    .font(Theme.mono(10)).foregroundStyle(Theme.faint).textSelection(.enabled)
                            }
                        }.font(Theme.sans(12)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                    HStack {
                        if let url = safeURL(record.originalURL) { Link("Original article", destination: url) }
                        if let url = safeURL(record.sourceURL) { Link("Provider record", destination: url) }
                        if store.saved.contains(where: { $0.recordId == record.id }) {
                            Text("Saved to Knowledge").foregroundStyle(Theme.muted)
                        }
                    }.font(Theme.sans(11))
                }.padding(16).background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
            }
        }
    }

    private func safeURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
