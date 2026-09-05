import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeView: View {
    @ObservedObject var store: KnowledgeLibraryStore
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            scopeSummary
            if !store.error.isEmpty {
                Label(LocalizedStringKey(store.error), systemImage: "exclamationmark.triangle")
                    .font(Theme.sans(12)).foregroundStyle(Theme.danger).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.danger.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("knowledge-error")
            }
            searchPanel
            if store.hasSearched { searchResults }
            inventoryPanel
        }
        .padding(.horizontal, 32).padding(.vertical, 28)
        .frame(maxWidth: 1200, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { store.reload() }
        .sheet(isPresented: Binding(
            get: { store.selectedPath != nil },
            set: { if !$0 { store.selectFile(nil) } }
        )) { KnowledgeFileDetail(store: store).environment(\.locale, locale) }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom) { heading; Spacer(); actions }
            VStack(alignment: .leading, spacing: 12) { heading; actions }
        }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Knowledge").font(Theme.serif(30)).foregroundStyle(Theme.ink)
                .accessibilityIdentifier("knowledge-heading")
            Text("Your sources, notes and reviewed knowledge, organized by project.")
                .font(Theme.sans(12.5)).foregroundStyle(Theme.faint)
        }
    }
    private var actions: some View {
        HStack(spacing: 8) {
            Button { store.reload() } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh knowledge").accessibilityLabel("Refresh knowledge")
                .accessibilityIdentifier("refresh-knowledge-button")
                .disabled(store.isLoading || store.isWorking)
            Button("Open folder") { store.openFolder() }
            Button("Import files…") { importFiles() }
                .buttonStyle(.borderedProminent).disabled(store.isWorking)
                .accessibilityIdentifier("import-knowledge-button")
        }.buttonStyle(.bordered)
    }

    private var scopeSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("Knowledge scope", selection: Binding(
                    get: { store.scope }, set: { store.selectScope($0) }
                )) {
                    Text("Global").tag(KnowledgeLibraryScope.global)
                    if store.projectRoot != nil { Text("Project").tag(KnowledgeLibraryScope.project) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 260)
                .accessibilityIdentifier("knowledge-scope-picker")
                if store.scope == .project {
                    Text(store.projectName).font(Theme.sans(12, weight: .medium)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(PiFormat.path(store.knowledgeRoot.path))
                .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 80), spacing: 12), count: 4), spacing: 12) {
                stat("Files", value: store.inventory.map { "\($0.fileCount)" } ?? "—", identifier: "knowledge-file-count")
                stat("Total size", value: store.inventory.map { KnowledgeFormat.bytes($0.totalBytes) } ?? "—", identifier: "knowledge-total-size")
                stat("Knowledge cards", value: count("cards"))
                stat("Drafts", value: count("drafts"))
            }
            Text("Size includes source files and attachments; hidden files and links are excluded.")
                .font(Theme.sans(11)).foregroundStyle(Theme.faint)
            HStack(spacing: 10) {
                if store.isLoading || store.isWorking { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(store.isLoading ? "Loading knowledge…" :
                        (store.status.isEmpty ? (store.inventory?.initialized == true ? "Index ready" : "Not indexed yet") : store.status)))
                        .font(Theme.mono(10)).foregroundStyle(Theme.muted)
                    if let date = store.inventory?.latestRun?.date {
                        Text("Last indexed: \(date.formatted(.dateTime.year().month().day().hour().minute().locale(locale)))")
                            .font(Theme.mono(9.5)).foregroundStyle(Theme.faint)
                    }
                }
                Spacer()
                Menu { Button("Rebuild index") { store.index(rebuild: true) } }
                    label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(store.isWorking)
                Button("Update index") { store.index() }
                    .buttonStyle(.bordered).disabled(store.isWorking)
                    .accessibilityIdentifier("index-knowledge-button")
            }
        }
    }
    private func stat(_ title: LocalizedStringKey, value: String, identifier: String = "") -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(Theme.sans(11)).foregroundStyle(Theme.faint)
            Text(value).font(Theme.mono(22)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6).accessibilityIdentifier(identifier)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }
    private func count(_ category: String) -> String {
        store.inventory.map { "\($0.categories[category]?.files ?? 0)" } ?? "—"
    }
    private var searchPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
            TextField("Search knowledge content", text: $store.query)
                .textFieldStyle(.plain).onSubmit { store.search() }
                .accessibilityIdentifier("knowledge-search-input")
            if store.isSearching { ProgressView().controlSize(.small) }
            if store.hasSearched { Button("Clear") { store.clearSearch() }.buttonStyle(.borderless) }
            Button("Search") { store.search() }
                .disabled(store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSearching || store.isWorking)
                .accessibilityIdentifier("knowledge-search-button")
        }
        .padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
    }
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search results").font(Theme.sans(14, weight: .medium))
            Text("Search includes registered sources and reviewed cards. Drafts and inbox are excluded.")
                .font(Theme.sans(11)).foregroundStyle(Theme.faint)
            if store.results.isEmpty && !store.isSearching && store.error.isEmpty {
                Text("No matching knowledge found.").font(Theme.sans(12)).foregroundStyle(Theme.muted)
            }
            ForEach(store.results) { hit in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(hit.document.title).font(Theme.sans(13, weight: .medium))
                        Spacer()
                        Button("Open source") { openFile(hit.document.relativePath) }.buttonStyle(.borderless)
                    }
                    Text(hit.chunk.locator).font(Theme.mono(10)).foregroundStyle(Theme.accent)
                    Text(hit.chunk.text).font(Theme.sans(12)).foregroundStyle(Theme.body)
                        .lineLimit(6).textSelection(.enabled)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("knowledge-search-results")
    }
    private var inventoryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Library contents").font(Theme.sans(15, weight: .medium))
                Spacer()
                TextField("Filter filenames", text: $store.fileFilter)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 230)
                    .accessibilityIdentifier("knowledge-file-filter")
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { categories.frame(width: 155); files }
                VStack(alignment: .leading, spacing: 14) { categories; files }
            }
            if store.inventory?.truncated == true {
                Text("Showing the first 5,000 files. Totals include all files; open the folder to see the rest.")
                    .font(Theme.sans(11)).foregroundStyle(Theme.warning)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("knowledge-library-contents")
    }
    private var categories: some View {
        VStack(alignment: .leading, spacing: 3) {
            categoryRow(nil, title: "All files", count: store.inventory?.fileCount ?? 0)
            ForEach(KnowledgeCategory.all, id: \.self) { category in
                categoryRow(category, title: KnowledgeCategory.title(category), count: store.inventory?.categories[category]?.files ?? 0)
            }
        }
    }
    private func categoryRow(_ value: String?, title: String, count: Int) -> some View {
        Button { store.category = value } label: {
            HStack {
                Text(LocalizedStringKey(title)).font(Theme.sans(12))
                Spacer(minLength: 12)
                Text("\(count)").font(Theme.mono(10)).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .foregroundStyle(store.category == value ? Theme.accent : Theme.secondary)
            .background(store.category == value ? Theme.selected : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityIdentifier("knowledge-category-\(value ?? "all")")
    }
    private var files: some View {
        LazyVStack(spacing: 0) {
            if store.visibleFiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray").font(.system(size: 23)).foregroundStyle(Theme.pale)
                    Text(store.isLoading ? "Loading knowledge…" : "No files in this selection.")
                        .font(Theme.sans(12)).foregroundStyle(Theme.faint)
                    Text("Import Markdown, TXT or PDF files to begin.").font(Theme.sans(11)).foregroundStyle(Theme.faint)
                }.padding(28).frame(maxWidth: .infinity)
            }
            ForEach(store.visibleFiles) { file in
                Button { store.selectFile(file.relativePath) } label: {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: file.extension == ".pdf" ? "doc.richtext" : "doc.text")
                            .foregroundStyle(Theme.accent).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.index?.title ?? file.name)
                                .font(Theme.sans(12.5, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(file.relativePath).font(Theme.mono(9.5)).foregroundStyle(Theme.faint)
                                .lineLimit(1).truncationMode(.middle)
                            Text(LocalizedStringKey(KnowledgeCategory.status(file))).font(Theme.mono(9.5))
                                .foregroundStyle(file.index?.error != nil ? Theme.danger : Theme.muted)
                        }
                        Spacer(minLength: 5)
                        Text(KnowledgeFormat.bytes(file.sizeBytes)).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    }.padding(13).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("knowledge-file-\(file.relativePath)")
                Hairline()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
    }
    private func importFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .plainText, UTType(filenameExtension: "md") ?? .text, UTType(filenameExtension: "markdown") ?? .text]
        guard panel.runModal() == .OK else { return }
        store.importFiles(panel.urls)
    }
    private func openFile(_ path: String) {
        if let url = store.fileURL(path) { NSWorkspace.shared.open(url) }
    }
}

private struct KnowledgeFileDetail: View {
    @ObservedObject var store: KnowledgeLibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(store.selectedFile?.index?.title ?? store.selectedFile?.name ?? "")
                    .font(Theme.serif(24)).lineLimit(2)
                Spacer()
                Button("Close") { store.selectFile(nil) }.keyboardShortcut(.cancelAction)
            }
            if let file = store.selectedFile {
                Text(file.relativePath).font(Theme.mono(11)).foregroundStyle(Theme.faint).textSelection(.enabled)
                HStack(spacing: 16) {
                    Text(KnowledgeFormat.bytes(file.sizeBytes))
                    Text(LocalizedStringKey(KnowledgeCategory.status(file)))
                    if let date = file.modifiedDate { Text(date, style: .date) }
                }.font(Theme.mono(11)).foregroundStyle(Theme.muted)
                if let error = file.index?.error {
                    Text(error).font(Theme.sans(12)).foregroundStyle(Theme.danger).textSelection(.enabled)
                }
                if file.index?.stale == true {
                    Text("This file changed after indexing. Update the index to refresh its preview.")
                        .font(Theme.sans(12)).foregroundStyle(Theme.warning)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if store.isReading { ProgressView() }
                        if let document = store.document {
                            ForEach(Array(document.chunks.prefix(50)), id: \.id) { chunk in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(chunk.locator).font(Theme.mono(10)).foregroundStyle(Theme.accent)
                                    Text(chunk.text).font(Theme.sans(12.5)).foregroundStyle(Theme.body)
                                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            if document.chunks.count > 50 {
                                Text("Preview limited to 50 sections. Open the source to read the complete file.")
                                    .font(Theme.sans(11)).foregroundStyle(Theme.faint)
                            }
                        } else if !store.isReading {
                            Text("Update the index to preview supported files, or open the original.")
                                .font(Theme.sans(12)).foregroundStyle(Theme.faint)
                        }
                    }.padding(.vertical, 8)
                }
                HStack {
                    Button("Open source") {
                        if let url = store.fileURL(file.relativePath) { NSWorkspace.shared.open(url) }
                    }
                    Button("Show in Finder") {
                        if let url = store.fileURL(file.relativePath) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Spacer()
                    if store.canPublish {
                        Button("Publish reviewed card") { store.publishSelectedCard() }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("publish-knowledge-button")
                    }
                }
            }
        }
        .padding(24).frame(width: 660, height: 560).background(Theme.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("knowledge-file-detail")
    }
}

struct SidebarKnowledgeSummary: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: KnowledgeLibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            MonoLabel(text: "Knowledge", size: 9.5)
            if store.projectRoot != nil { entry(summary: store.projectSummary, scope: .project) }
            entry(summary: store.globalSummary, scope: .global)
        }
        .padding(10).background(Theme.panel, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar-knowledge-summary")
    }
    private func entry(summary: KnowledgeDirectorySummary?, scope: KnowledgeLibraryScope) -> some View {
        Button {
            appState.selectedSection = .knowledge
            store.selectScope(scope)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Group {
                    if scope == .global { Text("Global knowledge") }
                    else { Text(store.projectName) }
                }.font(Theme.sans(11.5, weight: .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                if let summary {
                    if summary.error != nil {
                        Text("Unable to read knowledge folder").font(Theme.mono(9)).foregroundStyle(Theme.warning)
                    } else {
                        HStack(spacing: 5) {
                            Text("\(summary.fileCount) files")
                            Text("·")
                            Text(KnowledgeFormat.bytes(summary.totalBytes))
                        }.font(Theme.mono(9)).foregroundStyle(Theme.faint)
                    }
                } else {
                    Text("Loading knowledge…").font(Theme.mono(9)).foregroundStyle(Theme.faint)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("sidebar-knowledge-\(scope.rawValue)")
    }
}

enum KnowledgeCategory {
    static let all = ["sources", "cards", "drafts", "inbox", "attachments", "entries", "other"]
    static func title(_ category: String) -> String {
        switch category {
        case "sources": "Sources"
        case "cards": "Knowledge cards"
        case "drafts": "Drafts"
        case "inbox": "Inbox"
        case "attachments": "Attachments"
        case "entries": "Legacy entries"
        default: "Other files"
        }
    }
    static func status(_ file: KnowledgeFileEntry) -> String {
        guard let index = file.index else { return file.supported ? "Not indexed yet" : "Stored file" }
        if index.error != nil { return "Indexing failed" }
        if index.stale == true { return "Index needs update" }
        if index.status == "draft" { return "Draft · excluded from search" }
        if index.status == "inbox" { return "Inbox · excluded from search" }
        if index.status == "deprecated" { return "Deprecated · excluded from search" }
        if index.chunks == 0 { return "No extractable text" }
        return index.status == "reviewed" ? "Reviewed" : "Indexed"
    }
}
