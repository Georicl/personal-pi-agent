import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkbenchSidebarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var texts: WorkbenchStore
    @ObservedObject var figures: FigureArtifactStore
    @State private var kind = "figure"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Research outputs").font(.headline)
                Spacer()
                Button { importText() } label: { Image(systemName: "doc.badge.plus") }
                    .help("Import Markdown or text")
                    .accessibilityIdentifier("import-workbench-text")
                Button { appState.isArtifactSidebarVisible = false } label: { Image(systemName: "xmark") }
                    .help("Close preview")
            }.padding(12)
            Picker("Output type", selection: $kind) {
                Text("Figures").tag("figure")
                Text("Text").tag("text")
            }.pickerStyle(.segmented).padding(.horizontal, 12).padding(.bottom, 8)
                .accessibilityIdentifier("workbench-output-type")
            if kind == "text" {
                TextArtifactPanel(store: texts, onReview: appState.addReview)
            } else {
                let scoped = figures.artifacts.filter {
                    WorkbenchStore.canonical($0.cwd) == WorkbenchStore.canonical(appState.activeWorkingDirectory)
                }
                if !scoped.isEmpty {
                    Picker("Figure", selection: $figures.selectedArtifactID) {
                        ForEach(scoped) { artifact in
                            Text("\(artifact.title) · v\(artifact.version)").tag(Optional(artifact.id))
                        }
                    }.padding(.horizontal, 12)
                }
                if let selected = figures.selectedArtifact,
                   WorkbenchStore.canonical(selected.cwd) == WorkbenchStore.canonical(appState.activeWorkingDirectory) {
                    ArtifactSidebarView(isVisible: $appState.isArtifactSidebarVisible, store: figures,
                                        onReview: appState.addReview, showsHeader: false)
                } else {
                    Text("No figure yet").foregroundStyle(.secondary).padding()
                    Spacer()
                }
            }
        }
        .background(Theme.panel)
        .onAppear { if texts.selected != nil { kind = "text" }; texts.refresh() }
        .onChange(of: texts.selectedID) { value in if value != nil { kind = "text" } }
        .onChange(of: figures.selectedArtifactID) { value in if value != nil { kind = "figure" } }
    }

    private func importText() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            texts.importFile(url)
            kind = "text"
        }
    }
}

struct TextArtifactPanel: View {
    @ObservedObject var store: WorkbenchStore
    var onReview: (ArtifactReviewAttachment) -> Void
    @State private var content = ""
    @State private var previous = ""
    @State private var range = NSRange(location: 0, length: 0)
    @State private var comment = ""
    @State private var error = ""
    @State private var loadedID: String?
    @State private var rendered = false
    @State private var comparing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.error.isEmpty { Text(store.error).font(.caption).foregroundStyle(.red) }
            if let artifact = store.selected {
                Picker("Document version", selection: $store.selectedID) {
                    ForEach(store.artifacts) { item in
                        Text("\(item.title) · v\(item.version)").tag(Optional(item.id))
                    }
                }.accessibilityIdentifier("text-artifact-picker")
                HStack {
                    Toggle("Rendered preview", isOn: $rendered).toggleStyle(.checkbox)
                    Spacer()
                    Button { export(artifact) } label: { Image(systemName: "square.and.arrow.up") }
                        .help("Export text…")
                        .disabled(loadedID != artifact.id)
                }.font(.caption)
                if rendered {
                    ScrollView {
                        Text((try? AttributedString(markdown: content)) ?? AttributedString(content))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10).textSelection(.enabled)
                    }.frame(minHeight: 180)
                    Text("Switch off rendered preview to select exact source text for review.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    SelectableReviewText(text: content, selection: $range)
                        .frame(minHeight: 180)
                        .accessibilityIdentifier("text-artifact-source")
                }
                if artifact.parentVersion != nil {
                    Toggle("Compare with previous version", isOn: $comparing).toggleStyle(.checkbox).font(.caption)
                    if comparing {
                        Text("− Previous · + Current").font(.caption).foregroundStyle(.secondary)
                        SelectableReviewText(text: TextRevisionDiff.make(old: previous, new: content), selection: .constant(NSRange()))
                            .frame(height: 170).accessibilityIdentifier("text-version-comparison")
                    }
                }
                TextField("Describe the revision…", text: $comment, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("text-review-comment")
                Button("Add selection to chat") {
                    do {
                        let attachment = try ArtifactReviewAttachment.text(artifact, content: content, range: range, comment: comment)
                        onReview(attachment)
                        comment = ""
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(loadedID != artifact.id || range.length == 0 || rendered || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("add-text-review")
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            } else {
                Text("Import a Markdown/TXT file, or ask Pi to create a research text with /workbench.")
                    .foregroundStyle(.secondary).padding()
                Spacer()
            }
        }
        .padding(12)
        .task(id: store.selectedID) {
            loadedID = nil; content = ""; previous = ""; range = NSRange(); comment = ""; error = ""
            guard let artifact = store.selected else { return }
            let result = await Task.detached(priority: .utility) {
                Result { () -> (String, String) in
                    let current = try WorkbenchClient.execute(.init(action: "read", cwd: artifact.cwd,
                        artifactId: artifact.artifactId, version: artifact.version)).content ?? ""
                    var previous = ""
                    if let parent = artifact.parentVersion {
                        previous = try WorkbenchClient.execute(.init(action: "read", cwd: artifact.cwd,
                            artifactId: artifact.artifactId, version: parent)).content ?? ""
                    }
                    return (current, previous)
                }
            }.value
            guard !Task.isCancelled, store.selectedID == artifact.id else { return }
            switch result {
            case .success(let values): content = values.0; previous = values.1; loadedID = artifact.id
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    private func export(_ artifact: TextArtifact) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = artifact.title.lowercased().hasSuffix(".md") ? artifact.title : "\(artifact.title).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        let snapshot = content
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                guard WorkbenchStore.canonical(url.path) != WorkbenchStore.canonical(artifact.sourcePath) else {
                    throw WorkbenchError.message("Export to a separate file to preserve the reviewed version")
                }
                try snapshot.write(to: url, atomically: true, encoding: .utf8)
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct SelectableReviewText: NSViewRepresentable {
    let text: String
    @Binding var selection: NSRange
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.delegate = context.coordinator
        view.setAccessibilityIdentifier("review-selectable-text")
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = view.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text; textView.setSelectedRange(NSRange()) }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableReviewText
        init(_ parent: SelectableReviewText) { self.parent = parent }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.selection = view.selectedRange()
        }
    }
}

enum TextRevisionDiff {
    static func make(old: String, new: String) -> String {
        let before = old.components(separatedBy: "\n"), after = new.components(separatedBy: "\n")
        let differences = after.difference(from: before)
        var removals = Set<Int>(), insertions = Set<Int>()
        for change in differences {
            switch change {
            case .remove(let offset, _, _): removals.insert(offset)
            case .insert(let offset, _, _): insertions.insert(offset)
            }
        }
        var lines: [String] = [], i = 0, j = 0
        while i < before.count || j < after.count {
            if i < before.count, removals.contains(i) { lines.append("− " + before[i]); i += 1 }
            else if j < after.count, insertions.contains(j) { lines.append("+ " + after[j]); j += 1 }
            else if j < after.count { lines.append("  " + after[j]); i += 1; j += 1 }
            else { i += 1 }
        }
        return lines.joined(separator: "\n")
    }
}

struct FigureReviewPreview: View {
    let artifact: FigureArtifact
    let onReview: (ArtifactReviewAttachment) -> Void
    @State private var image: NSImage?
    @State private var region: ReviewRegion?
    @State private var comment = ""
    @State private var error = ""
    @State private var preparing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image).resizable().frame(width: geometry.size.width, height: geometry.size.height)
                        if let region {
                            Rectangle().stroke(.red, lineWidth: 2)
                                .frame(width: region.width * geometry.size.width, height: region.height * geometry.size.height)
                                .offset(x: region.x * geometry.size.width, y: region.y * geometry.size.height)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                        region = ReviewRegion.selection(start: value.startLocation, end: value.location, size: geometry.size)
                    })
                }
                .aspectRatio(image.size.width / max(1, image.size.height), contentMode: .fit)
                .accessibilityIdentifier("figure-review-canvas")
                Text("Drag to select a region, then describe the change.").font(.caption).foregroundStyle(.secondary)
                TextField("Describe the revision…", text: $comment, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("figure-review-comment")
                Button("Add selection to chat") {
                    guard let region else { return }
                    let comment = comment
                    preparing = true
                    Task {
                        let result = await Task.detached(priority: .utility) {
                            Result { try ArtifactReviewAttachment.figure(artifact, region: region, comment: comment) }
                        }.value
                        preparing = false
                        switch result {
                        case .success(let attachment): onReview(attachment); self.comment = ""
                        case .failure(let failure): error = failure.localizedDescription
                        }
                    }
                }.disabled(region == nil || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || preparing)
                    .accessibilityIdentifier("add-figure-review")
            } else {
                Text("Loading preview…")
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .task(id: artifact.id) {
            image = nil; region = nil; comment = ""; error = ""
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: artifact.previewURL) }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap(NSImage.init(data:))
            if image == nil { error = "Preview file is unavailable" }
        }
    }
}
