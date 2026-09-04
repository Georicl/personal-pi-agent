import Combine
import Foundation

enum FigureExportFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case png
    case tiff
    case pdf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: "PNG"
        case .tiff: "TIFF"
        case .pdf: "PDF"
        }
    }

    var filenameExtension: String { rawValue }
}

struct FigureArtifactFile: Codable, Hashable, Sendable {
    let format: FigureExportFormat
    let path: String

    var url: URL { URL(fileURLWithPath: path) }
}

struct FigureValidationCheck: Codable, Hashable, Sendable, Identifiable {
    let name: String
    let passed: Bool
    let count: Int?

    var id: String { name }
}

struct FigureValidation: Codable, Hashable, Sendable {
    let passed: Bool
    let score: Int
    let errors: [String]
    let warnings: [String]
    let checks: [FigureValidationCheck]
}

struct FigureArtifact: Codable, Hashable, Sendable, Identifiable {
    let schemaVersion: Int
    let kind: String
    let id: String
    let figureId: String
    let version: Int
    let title: String
    let sessionId: String?
    let cwd: String
    let createdAt: Date
    let previewPath: String
    let files: [FigureArtifactFile]
    let widthMm: Double
    let heightMm: Double
    let dpi: Int
    let validation: FigureValidation
    let intermediatesRetained: Bool

    var previewURL: URL { URL(fileURLWithPath: previewPath) }

    var availableFormats: [FigureExportFormat] {
        FigureExportFormat.allCases.filter { format in
            files.contains { $0.format == format }
        }
    }

    func fileURL(for format: FigureExportFormat) -> URL? {
        files.first(where: { $0.format == format })?.url
    }

    static func decode(_ object: Any?) -> FigureArtifact? {
        guard let object,
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? decoder.decode(FigureArtifact.self, from: data)
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 figure timestamp: \(value)"
            )
        }
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

@MainActor
final class FigureArtifactStore: ObservableObject {
    @Published private(set) var artifacts: [FigureArtifact] = []
    @Published var selectedArtifactID: String?

    let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL
            ?? PersonalPiRuntimeEnvironment.piRootURL
                .appendingPathComponent("agent", isDirectory: true)
                .appendingPathComponent("personal-pi-figure-artifacts.json")
        load()
    }

    var selectedArtifact: FigureArtifact? {
        guard let selectedArtifactID else { return nil }
        return artifacts.first { $0.id == selectedArtifactID }
    }

    var hasArtifacts: Bool { !artifacts.isEmpty }

    func versions(for artifact: FigureArtifact) -> [FigureArtifact] {
        artifacts
            .filter {
                $0.figureId == artifact.figureId
                    && $0.cwd == artifact.cwd
                    && $0.sessionId == artifact.sessionId
            }
            .sorted { $0.version > $1.version }
    }

    func select(_ artifact: FigureArtifact) {
        selectedArtifactID = artifact.id
    }

    func selectLatest(sessionId: String?, cwd: String) {
        if let sessionId,
           let exact = artifacts.first(where: { $0.sessionId == sessionId }) {
            selectedArtifactID = exact.id
            return
        }
        let standardizedCWD = standardizedPath(cwd)
        if let exact = artifacts.first(where: {
            standardizedPath($0.cwd) == standardizedCWD
        }) {
            selectedArtifactID = exact.id
            return
        }
        let normalizedCWD = canonicalPath(cwd)
        selectedArtifactID = artifacts.first(where: {
            canonicalPath($0.cwd) == normalizedCWD
        })?.id
    }

    func upsert(_ artifact: FigureArtifact) {
        guard artifact.kind == "scientific-figure", artifact.schemaVersion == 1 else { return }
        if let index = artifacts.firstIndex(where: { $0.id == artifact.id }) {
            artifacts[index] = artifact
        } else {
            artifacts.append(artifact)
        }
        artifacts.sort { $0.createdAt > $1.createdAt }
        selectedArtifactID = artifact.id
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? FigureArtifact.decoder.decode([FigureArtifact].self, from: data) else {
            return
        }
        artifacts = decoded
            .filter { artifact in
                artifact.files.contains { FileManager.default.fileExists(atPath: $0.path) }
            }
            .sorted { $0.createdAt > $1.createdAt }
        selectedArtifactID = artifacts.first?.id
        if artifacts.count != decoded.count { persist() }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var data = try FigureArtifact.encoder.encode(artifacts)
            data.append(0x0A)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Figure files remain usable even if the optional GUI index cannot be written.
        }
    }

    private func canonicalPath(_ raw: String) -> String {
        URL(fileURLWithPath: raw).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func standardizedPath(_ raw: String) -> String {
        URL(fileURLWithPath: raw).standardizedFileURL.path
    }
}
