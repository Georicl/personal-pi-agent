import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FigureExportError: LocalizedError, Equatable {
    case invalidWidth
    case invalidHeight
    case invalidDPI
    case missingSource
    case unreadableSource
    case cannotCreateOutput
    case cannotWriteOutput

    var errorDescription: String? {
        localizedDescription(locale: .current)
    }

    func localizedDescription(locale: Locale) -> String {
        switch self {
        case .invalidWidth: String(localized: "Width must be greater than 0 and no more than 210 mm.", locale: locale)
        case .invalidHeight: String(localized: "Height must be greater than 0 and no more than 148.5 mm.", locale: locale)
        case .invalidDPI: String(localized: "Raster DPI must be between 72 and 1200.", locale: locale)
        case .missingSource: String(localized: "The selected artifact does not contain that format.", locale: locale)
        case .unreadableSource: String(localized: "The figure source could not be read.", locale: locale)
        case .cannotCreateOutput: String(localized: "The export file could not be created.", locale: locale)
        case .cannotWriteOutput: String(localized: "The export file could not be written.", locale: locale)
        }
    }
}

enum FigureExporter {
    static let defaultWidthMm = 210.0
    static let defaultHeightMm = 74.25
    static let defaultDPI = 300
    static let maximumWidthMm = 210.0
    static let maximumHeightMm = 148.5

    static func validate(
        format: FigureExportFormat,
        widthMm: Double,
        heightMm: Double,
        dpi: Int
    ) throws {
        guard widthMm.isFinite, widthMm > 0, widthMm <= maximumWidthMm else {
            throw FigureExportError.invalidWidth
        }
        guard heightMm.isFinite, heightMm > 0, heightMm <= maximumHeightMm else {
            throw FigureExportError.invalidHeight
        }
        if format != .pdf, !(72...1200).contains(dpi) {
            throw FigureExportError.invalidDPI
        }
    }

    static func export(
        artifact: FigureArtifact,
        format: FigureExportFormat,
        destination: URL,
        widthMm: Double,
        heightMm: Double,
        dpi: Int
    ) throws {
        try validate(format: format, widthMm: widthMm, heightMm: heightMm, dpi: dpi)
        guard existingFileURL(for: format, in: artifact) != nil else {
            throw FigureExportError.missingSource
        }

        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".personal-pi-export-\(UUID().uuidString).\(format.filenameExtension)"
        )
        defer { try? FileManager.default.removeItem(at: temporary) }

        if format == .pdf {
            guard let source = existingFileURL(for: .pdf, in: artifact) else {
                throw FigureExportError.missingSource
            }
            try exportPDF(source: source, destination: temporary, widthMm: widthMm, heightMm: heightMm)
        } else {
            let image = try rasterizedImage(
                artifact: artifact,
                widthMm: widthMm,
                heightMm: heightMm,
                dpi: dpi
            )
            try writeRaster(image, format: format, destination: temporary, dpi: dpi)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(
                destination,
                withItemAt: temporary,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private static func exportPDF(
        source: URL,
        destination: URL,
        widthMm: Double,
        heightMm: Double
    ) throws {
        guard let document = CGPDFDocument(source as CFURL),
              let page = document.page(at: 1),
              let consumer = CGDataConsumer(url: destination as CFURL) else {
            throw FigureExportError.unreadableSource
        }
        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: points(fromMillimeters: widthMm),
            height: points(fromMillimeters: heightMm)
        )
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw FigureExportError.cannotCreateOutput
        }
        context.beginPDFPage(nil)
        context.saveGState()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(mediaBox)
        let transform = page.getDrawingTransform(
            .mediaBox,
            rect: mediaBox,
            rotate: 0,
            preserveAspectRatio: true
        )
        context.concatenate(transform)
        context.drawPDFPage(page)
        context.restoreGState()
        context.endPDFPage()
        context.closePDF()
    }

    private static func rasterizedImage(
        artifact: FigureArtifact,
        widthMm: Double,
        heightMm: Double,
        dpi: Int
    ) throws -> CGImage {
        let pixelWidth = max(1, Int((widthMm / 25.4 * Double(dpi)).rounded()))
        let pixelHeight = max(1, Int((heightMm / 25.4 * Double(dpi)).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw FigureExportError.cannotCreateOutput
        }

        let target = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(target)

        if let pdfURL = existingFileURL(for: .pdf, in: artifact),
           let document = CGPDFDocument(pdfURL as CFURL),
           let page = document.page(at: 1) {
            let transform = page.getDrawingTransform(
                .mediaBox,
                rect: target,
                rotate: 0,
                preserveAspectRatio: true
            )
            context.saveGState()
            context.concatenate(transform)
            context.drawPDFPage(page)
            context.restoreGState()
        } else {
            guard let sourceURL = existingFileURL(for: .png, in: artifact)
                    ?? existingFileURL(for: .tiff, in: artifact),
                  let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw FigureExportError.unreadableSource
            }
            context.interpolationQuality = .high
            context.draw(image, in: aspectFit(
                source: CGSize(width: image.width, height: image.height),
                target: target
            ))
        }

        guard let image = context.makeImage() else { throw FigureExportError.cannotCreateOutput }
        return image
    }

    private static func writeRaster(
        _ image: CGImage,
        format: FigureExportFormat,
        destination: URL,
        dpi: Int
    ) throws {
        let type: UTType
        switch format {
        case .png: type = .png
        case .tiff: type = .tiff
        case .pdf: throw FigureExportError.cannotWriteOutput
        }
        guard let output = CGImageDestinationCreateWithURL(
            destination as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw FigureExportError.cannotCreateOutput
        }

        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        if format == .tiff {
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFCompression: 5,
            ]
        }
        CGImageDestinationAddImage(output, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw FigureExportError.cannotWriteOutput }
    }

    private static func aspectFit(source: CGSize, target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return target }
        let scale = min(target.width / source.width, target.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: target.midX - size.width / 2,
            y: target.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func points(fromMillimeters value: Double) -> Double {
        value / 25.4 * 72
    }

    private static func existingFileURL(
        for format: FigureExportFormat,
        in artifact: FigureArtifact
    ) -> URL? {
        guard let url = artifact.fileURL(for: format),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
