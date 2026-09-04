import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ArtifactSidebarView: View {
    @Binding var isVisible: Bool
    @ObservedObject var store: FigureArtifactStore
    @State private var showingExport = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if let artifact = store.selectedArtifact {
                ScrollView(showsIndicators: false) {
                    artifactContent(artifact)
                        .padding(16)
                }
                .sheet(isPresented: $showingExport) {
                    FigureExportSheet(artifact: artifact)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
        .accessibilityIdentifier("figure-artifact-sidebar")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(Theme.accent)
            Text("Figure preview")
                .font(Theme.sans(12.5, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Button {
                isVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close figure preview")
            .accessibilityIdentifier("close-figure-artifact-sidebar")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(Theme.pale)
            Text("No figure yet")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            Text("Figures created by the scientific plotting workflow will appear here automatically.")
                .font(Theme.sans(10.5))
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .accessibilityIdentifier("figure-artifact-empty-state")
    }

    @ViewBuilder
    private func artifactContent(_ artifact: FigureArtifact) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(artifact.title)
                    .font(Theme.serif(19, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                HStack(spacing: 7) {
                    Text("v\(artifact.version)")
                    Text("·")
                    Text(artifact.createdAt, style: .relative)
                }
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.dim)
            }

            preview(artifact)

            if store.versions(for: artifact).count > 1 {
                versionPicker(artifact)
            }

            validationCard(artifact.validation)

            VStack(alignment: .leading, spacing: 7) {
                metadataRow("Size", value: String(format: "%.2f × %.2f mm", artifact.widthMm, artifact.heightMm))
                metadataRow("Raster DPI", value: "\(artifact.dpi)")
                metadataRow("Formats", value: artifact.availableFormats.map(\.displayName).joined(separator: " · "))
                metadataRow("Location", value: PiFormat.path(artifact.cwd))
            }

            Button {
                showingExport = true
            } label: {
                Label("Export figure…", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(artifact.availableFormats.isEmpty)
            .accessibilityIdentifier("export-figure-button")
        }
    }

    @ViewBuilder
    private func preview(_ artifact: FigureArtifact) -> some View {
        ArtifactPreviewImage(url: artifact.previewURL)
    }

    private func versionPicker(_ artifact: FigureArtifact) -> some View {
        HStack(spacing: 10) {
            Text("Version")
                .font(Theme.sans(10.5, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 0)
            Picker("Version", selection: Binding(
                get: { store.selectedArtifactID ?? artifact.id },
                set: { identifier in
                    if let version = store.versions(for: artifact).first(where: { $0.id == identifier }) {
                        store.select(version)
                    }
                }
            )) {
                ForEach(store.versions(for: artifact)) { version in
                    Text("v\(version.version) · \(version.validation.score)/100")
                        .tag(version.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)
            .accessibilityIdentifier("figure-version-picker")
        }
    }

    private func validationCard(_ validation: FigureValidation) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: validation.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(validation.passed ? "Validation passed" : "Revision recommended")
                    .font(Theme.sans(11.5, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(validation.score)/100")
                    .font(Theme.mono(10, weight: .medium))
            }
            .foregroundStyle(validation.passed ? Theme.positive : Theme.warning)

            ForEach(validation.errors, id: \.self) { error in
                validationMessage(error, symbol: "xmark.circle", color: Theme.danger)
            }
            ForEach(validation.warnings, id: \.self) { warning in
                validationMessage(warning, symbol: "exclamationmark.circle", color: Theme.warning)
            }
        }
        .padding(11)
        .background(
            validation.passed ? Theme.accentFill : Theme.warningFill,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(validation.passed ? Theme.accentSoft : Theme.warningLine, lineWidth: 1)
        )
    }

    private func validationMessage(_ message: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(color)
                .padding(.top, 2)
            Text(message)
                .font(Theme.sans(9.5))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metadataRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(Theme.sans(10))
                .foregroundStyle(Theme.faint)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

private struct ArtifactPreviewImage: View {
    let url: URL
    @State private var image: NSImage?
    @State private var finishedLoading = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 360)
                    .padding(8)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Theme.line, lineWidth: 1)
                    )
                    .accessibilityIdentifier("figure-artifact-image")
            } else if finishedLoading {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Preview file is unavailable")
                        .font(Theme.sans(10.5))
                }
                .foregroundStyle(Theme.warning)
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(Theme.warningFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text("Loading preview…")
                        .font(Theme.sans(10.5))
                }
                .foregroundStyle(Theme.faint)
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task(id: url.path) {
            image = nil
            finishedLoading = false
            let data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap(NSImage.init(data:))
            finishedLoading = true
        }
    }
}

private struct FigureExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let artifact: FigureArtifact

    @State private var selectedFormat: FigureExportFormat
    @State private var widthMm = FigureExporter.defaultWidthMm
    @State private var heightMm = FigureExporter.defaultHeightMm
    @State private var dpi = FigureExporter.defaultDPI
    @State private var status = ""
    @State private var statusIsError = false

    init(artifact: FigureArtifact) {
        self.artifact = artifact
        _selectedFormat = State(initialValue: artifact.availableFormats.first ?? .png)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Export figure")
                    .font(Theme.serif(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Choose a supported format and final physical dimensions.")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.muted)
            }

            Form {
                Picker("Format", selection: $selectedFormat) {
                    ForEach(artifact.availableFormats) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                TextField("Width (mm)", value: $widthMm, format: .number.precision(.fractionLength(0...2)))
                TextField("Height (mm)", value: $heightMm, format: .number.precision(.fractionLength(0...2)))
                if selectedFormat == .pdf {
                    LabeledContent("DPI") {
                        Text("Not applicable to vector PDF")
                            .foregroundStyle(Theme.faint)
                    }
                } else {
                    TextField("DPI", value: $dpi, format: .number)
                }
            }
            .formStyle(.grouped)

            Text("Maximum: 210 × 148.5 mm. Raster default: 300 DPI.")
                .font(Theme.sans(10))
                .foregroundStyle(Theme.faint)

            if !status.isEmpty {
                Text(status)
                    .font(Theme.sans(10.5))
                    .foregroundStyle(statusIsError ? Theme.danger : Theme.positive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose destination…") { export() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("confirm-figure-export-button")
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func export() {
        do {
            try FigureExporter.validate(
                format: selectedFormat,
                widthMm: widthMm,
                heightMm: heightMm,
                dpi: dpi
            )
            let panel = NSSavePanel()
            panel.title = String(localized: "Export figure", locale: locale)
            panel.prompt = String(localized: "Export", locale: locale)
            panel.allowedContentTypes = [selectedFormat.contentType]
            panel.nameFieldStringValue = "\(safeFilename(artifact.title)).\(selectedFormat.filenameExtension)"
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try FigureExporter.export(
                artifact: artifact,
                format: selectedFormat,
                destination: destination,
                widthMm: widthMm,
                heightMm: heightMm,
                dpi: dpi
            )
            status = String(localized: "Figure exported", locale: locale)
            statusIsError = false
        } catch {
            if let exportError = error as? FigureExportError {
                status = exportError.localizedDescription(locale: locale)
            } else {
                status = error.localizedDescription
            }
            statusIsError = true
        }
    }

    private func safeFilename(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        let cleaned = raw.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "scientific-figure" : cleaned
    }
}

private extension FigureExportFormat {
    var contentType: UTType {
        switch self {
        case .png: .png
        case .tiff: .tiff
        case .pdf: .pdf
        }
    }
}
