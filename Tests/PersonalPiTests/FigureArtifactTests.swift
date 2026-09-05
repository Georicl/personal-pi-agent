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

    @Test("PDF rasterization preserves actual content coverage when enlarging and shrinking",
          arguments: [72, 150, 300, 600])
    func exportContentCoverage(dpi: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdf = directory.appendingPathComponent("source.pdf")
        let png = directory.appendingPathComponent("source.png")
        try makeTestPDF(at: pdf)
        try makeTestPNG(at: png)
        var object = manifestObject(previewPath: png.path)
        object["files"] = [["format": "pdf", "path": pdf.path], ["format": "png", "path": png.path],
                           ["format": "tiff", "path": png.path]]
        let artifact = try #require(FigureArtifact.decode(object))
        for format in [FigureExportFormat.png, .tiff, .pdf] {
            for width in [25.4, 210.0] {
                let output = directory.appendingPathComponent("export.\(format.filenameExtension)")
                try FigureExporter.export(artifact: artifact, format: format, destination: output,
                                          widthMm: width, heightMm: width / 2, dpi: dpi)
                let image: CGImage
                if format == .pdf {
                    // Independent rendering oracle: output media box is origin zero.
                    // Do not reuse FigureExporter's fitting transform to validate it.
                    let document = try #require(CGPDFDocument(output as CFURL))
                    let page = try #require(document.page(at: 1))
                    let box = page.getBoxRect(.mediaBox)
                    let ctx = try bitmapContext(width: 600, height: 300)
                    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                    ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
                    ctx.scaleBy(x: 600 / box.width, y: 300 / box.height)
                    ctx.drawPDFPage(page)
                    image = try #require(ctx.makeImage())
                } else {
                    let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
                    image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
                }
                let bounds = try coloredBounds(image)
                #expect(abs(bounds.width / Double(image.width) - 120.0 / 300) < 0.04)
                #expect(abs(bounds.height / Double(image.height) - 80.0 / 150) < 0.04)
                #expect(abs(bounds.minX / Double(image.width) - 20.0 / 300) < 0.04)
            }
        }
    }

    @Test("PDF fit includes nonzero page origins and rotation", arguments: [0, 90, 180, 270])
    func rotatedPageFit(rotation: Int) throws {
        let stream = "0.15 0.45 0.7 rg 50 30 100 200 re f"
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [50 30 150 230] /Rotate \(rotation) /Contents 4 0 R >>",
                       "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream"]
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 5\n0000000000 65535 f \n"
        pdf += offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        pdf += "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let provider = try #require(CGDataProvider(data: Data(pdf.utf8) as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let ctx = try bitmapContext(width: 800, height: 800)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
        ctx.concatenate(FigureExporter.fittingTransform(page: page, target: CGRect(x: 0, y: 0, width: 800, height: 800)))
        ctx.drawPDFPage(page)
        let bounds = try coloredBounds(try #require(ctx.makeImage()))
        #expect(abs(bounds.width - (rotation % 180 == 0 ? 400 : 800)) < 2)
        #expect(abs(bounds.height - (rotation % 180 == 0 ? 800 : 400)) < 2)
        #expect(abs(bounds.midX - 400) < 2)
        #expect(abs(bounds.midY - 400) < 2)
    }

    private func bitmapContext(width: Int, height: Int) throws -> CGContext {
        try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    private func coloredBounds(_ image: CGImage) throws -> CGRect {
        let ctx = try bitmapContext(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * ctx.bytesPerRow + x * 4
                if Int(bytes[offset + 2]) > Int(bytes[offset]) + 40 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        #expect(maxX >= minX && maxY >= minY, "Export lost all colored figure content")
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX + 1), height: max(0, maxY - minY + 1))
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
