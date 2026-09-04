import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import PersonalPi

@Suite("Figure artifacts")
struct FigureArtifactTests {
    @Test("Pi tool details decode into a figure artifact")
    func decodesToolResultArtifact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let preview = directory.appendingPathComponent("figure.png")
        let manifest = manifestObject(previewPath: preview.path)

        let event = try #require(PiRPCClient.parseEvent([
            "type": "tool_execution_end",
            "toolCallId": "tool-1",
            "toolName": "figure_render",
            "isError": false,
            "result": [
                "content": [["type": "text", "text": "Validation passed"]],
                "details": ["personalPiFigureArtifact": manifest],
            ],
        ]))

        let artifact = try #require(event.figureArtifact)
        #expect(artifact.id == "figure-1-v001")
        #expect(artifact.figureId == "figure-1")
        #expect(artifact.files.map(\.format) == [.png, .tiff, .pdf])
        #expect(artifact.validation.passed)
    }

    @Test("Artifact store persists versions and selects the latest session figure")
    @MainActor
    func persistsAndSelectsArtifacts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let index = directory.appendingPathComponent("artifacts.json")
        let preview = directory.appendingPathComponent("figure.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0]).write(to: preview)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifact = try #require(FigureArtifact.decode(manifestObject(previewPath: preview.path)))
        let store = FigureArtifactStore(storageURL: index)
        store.upsert(artifact)
        #expect(store.selectedArtifact?.id == artifact.id)

        let reloaded = FigureArtifactStore(storageURL: index)
        reloaded.selectLatest(sessionId: "session-1", cwd: "/tmp/project")
        #expect(reloaded.selectedArtifact?.id == artifact.id)
        #expect(reloaded.versions(for: artifact).count == 1)
    }

    @Test("Identical figure names remain isolated by project and session")
    @MainActor
    func isolatesFigureSeries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var firstObject = manifestObject(previewPath: "/tmp/first.png")
        firstObject["id"] = "project-a-v001"
        firstObject["cwd"] = "/tmp/project-a"
        var secondObject = manifestObject(previewPath: "/tmp/second.png")
        secondObject["id"] = "project-b-v001"
        secondObject["cwd"] = "/tmp/project-b"
        let first = try #require(FigureArtifact.decode(firstObject))
        let second = try #require(FigureArtifact.decode(secondObject))
        let store = FigureArtifactStore(storageURL: directory.appendingPathComponent("index.json"))
        store.upsert(first)
        store.upsert(second)

        #expect(store.versions(for: first).map(\.id) == [first.id])
        #expect(store.versions(for: second).map(\.id) == [second.id])
    }

    @Test("Legacy scientific-figure artifacts remain readable after plugin migration")
    @MainActor
    func acceptsLegacyArtifactKind() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var object = manifestObject(previewPath: "/tmp/legacy.png")
        object["kind"] = "scientific-figure"
        let artifact = try #require(FigureArtifact.decode(object))
        let store = FigureArtifactStore(storageURL: directory.appendingPathComponent("index.json"))
        store.upsert(artifact)

        #expect(store.artifacts.map(\.id) == [artifact.id])
    }

    @Test("Export dimensions and raster DPI obey publication bounds")
    func validatesExportBounds() throws {
        try FigureExporter.validate(format: .pdf, widthMm: 210, heightMm: 148.5, dpi: 1)
        try FigureExporter.validate(format: .png, widthMm: 210, heightMm: 74.25, dpi: 300)
        #expect(throws: FigureExportError.invalidWidth) {
            try FigureExporter.validate(format: .png, widthMm: 210.1, heightMm: 74.25, dpi: 300)
        }
        #expect(throws: FigureExportError.invalidHeight) {
            try FigureExporter.validate(format: .tiff, widthMm: 210, heightMm: 149, dpi: 300)
        }
        #expect(throws: FigureExportError.invalidDPI) {
            try FigureExporter.validate(format: .png, widthMm: 210, heightMm: 74.25, dpi: 50)
        }
    }

    @Test("Raster export applies requested pixels and DPI")
    func exportsRasterAtRequestedResolution() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        let output = directory.appendingPathComponent("output.png")
        try makeTestPNG(at: source)
        var object = manifestObject(previewPath: source.path)
        object["files"] = [["format": "png", "path": source.path]]
        let artifact = try #require(FigureArtifact.decode(object))
        try Data("previous export".utf8).write(to: output)

        try FigureExporter.export(
            artifact: artifact,
            format: .png,
            destination: output,
            widthMm: 25.4,
            heightMm: 12.7,
            dpi: 300
        )

        let sourceRef = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(sourceRef, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 300)
        #expect((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 150)
        #expect(abs(((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0) - 300) < 1)
    }

    @Test("Artifact sidebar renders without a page dependency")
    @MainActor
    func rendersArtifactSidebar() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let preview = directory.appendingPathComponent("preview.png")
        let index = directory.appendingPathComponent("index.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try makeTestPNG(at: preview)
        var object = manifestObject(previewPath: preview.path)
        object["files"] = [["format": "png", "path": preview.path]]
        let artifact = try #require(FigureArtifact.decode(object))
        let store = FigureArtifactStore(storageURL: index)
        store.upsert(artifact)

        let view = ArtifactSidebarView(isVisible: .constant(true), store: store)
            .frame(width: 440, height: 680)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        #expect(image.size.width == 440)
        #expect(image.size.height == 680)
    }

    @Test("TIFF and PDF exports preserve their distinct publication semantics")
    func exportsTIFFAndPDF() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = directory.appendingPathComponent("source.png")
        let tiff = directory.appendingPathComponent("source.tiff")
        let pdf = directory.appendingPathComponent("source.pdf")
        try makeTestPNG(at: png)
        try FileManager.default.copyItem(at: png, to: tiff)
        try makeTestPDF(at: pdf)
        var object = manifestObject(previewPath: png.path)
        object["files"] = [
            ["format": "png", "path": png.path],
            ["format": "tiff", "path": tiff.path],
            ["format": "pdf", "path": pdf.path],
        ]
        let artifact = try #require(FigureArtifact.decode(object))

        let exportedTIFF = directory.appendingPathComponent("exported.tiff")
        try FigureExporter.export(
            artifact: artifact,
            format: .tiff,
            destination: exportedTIFF,
            widthMm: 25.4,
            heightMm: 25.4,
            dpi: 150
        )
        let tiffSource = try #require(CGImageSourceCreateWithURL(exportedTIFF as CFURL, nil))
        let tiffProperties = try #require(CGImageSourceCopyPropertiesAtIndex(tiffSource, 0, nil) as? [CFString: Any])
        #expect((tiffProperties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 150)
        #expect((tiffProperties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 150)
        #expect(abs(((tiffProperties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0) - 150) < 1)
        let tiffMetadata = tiffProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect((tiffMetadata?[kCGImagePropertyTIFFCompression] as? NSNumber)?.intValue == 5)

        let exportedPDF = directory.appendingPathComponent("exported.pdf")
        try FigureExporter.export(
            artifact: artifact,
            format: .pdf,
            destination: exportedPDF,
            widthMm: 100,
            heightMm: 50,
            dpi: 1
        )
        let document = try #require(CGPDFDocument(exportedPDF as CFURL))
        let page = try #require(document.page(at: 1))
        #expect(abs(page.getBoxRect(.mediaBox).width - 100 / 25.4 * 72) < 0.1)
        #expect(abs(page.getBoxRect(.mediaBox).height - 50 / 25.4 * 72) < 0.1)
    }

    private func manifestObject(previewPath: String) -> [String: Any] {
        [
            "schemaVersion": 1,
            "kind": "figure",
            "id": "figure-1-v001",
            "figureId": "figure-1",
            "version": 1,
            "title": "Example figure",
            "sessionId": "session-1",
            "cwd": "/tmp/project",
            "createdAt": "2026-09-04T08:30:00.123Z",
            "previewPath": previewPath,
            "files": [
                ["format": "png", "path": previewPath],
                ["format": "tiff", "path": "/tmp/figure.tiff"],
                ["format": "pdf", "path": "/tmp/figure.pdf"],
            ],
            "widthMm": 210.0,
            "heightMm": 74.25,
            "dpi": 300,
            "validation": [
                "passed": true,
                "score": 100,
                "errors": [],
                "warnings": [],
                "checks": [["name": "pixel-dimensions", "passed": true]],
            ],
            "intermediatesRetained": false,
        ]
    }

    private func makeTestPNG(at url: URL) throws {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 2))
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 2))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func makeTestPDF(at url: URL) throws {
        let consumer = try #require(CGDataConsumer(url: url as CFURL))
        var mediaBox = CGRect(x: 0, y: 0, width: 300, height: 150)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.15, green: 0.45, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 20, y: 20, width: 120, height: 80))
        context.endPDFPage()
        context.closePDF()
    }
}
