import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SweepCore

final class IncomingInvoiceImageTests: XCTestCase {
    func testJPEGWithGenericFilenameIsNormalizedAndMetadataRemoved() throws {
        let bytes = try encoded(.jpeg)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
        try bytes.write(to: source); defer { try? FileManager.default.removeItem(at: source) }
        let result = try IncomingInvoiceImage.copy(from: source)
        defer { try? FileManager.default.removeItem(at: result) }
        try assertSanitized(result)
        XCTAssertEqual(try EvidenceFiles.imageExtension(result), "jpg")
    }

    func testTIFFAlternateRepresentationIsNormalizedToReadableJPEG() throws {
        let result = try IncomingInvoiceImage.copy(data: encoded(.tiff))
        defer { try? FileManager.default.removeItem(at: result) }
        XCTAssertEqual(try EvidenceFiles.imageExtension(result), "jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(result as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 733)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 1032)
    }

    func testJPEGDataProviderCanBeQueuedAndOutliveItsTemporaryInput() async throws {
        let bytes = try encoded(.jpeg)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier, visibility: .all) { done in done(bytes, nil); return nil }
        let result = try await SharedInvoiceLoader.load(from: provider)
        try assertSanitized(result)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: result) }
        let inbox = SharedInvoiceInbox(directory: root)
        let entry = try inbox.add(result)
        try FileManager.default.removeItem(at: result)
        XCTAssertEqual(try inbox.scan().items.count, 1)
        try EvidenceFiles.verify(entry.evidence, directory: entry.directory)
    }

    func testBrokenFileRepresentationFallsBackToJPEGData() async throws {
        let bytes = try encoded(.jpeg)
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("invalid file representation".utf8).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { done in done(broken, false, nil); return nil }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier, visibility: .all) { done in done(bytes, nil); return nil }
        let result = try await SharedInvoiceLoader.load(from: provider)
        defer { try? FileManager.default.removeItem(at: result) }
        try assertSanitized(result)
    }

    func testJPEGIsPreferredOverAnEarlierGenericRepresentation() async throws {
        let tiff = try encoded(.tiff), jpeg = try encoded(.jpeg)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.tiff.identifier, visibility: .all) { done in done(tiff, nil); return nil }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier, visibility: .all) { done in done(jpeg, nil); return nil }
        let result = try await SharedInvoiceLoader.load(from: provider)
        defer { try? FileManager.default.removeItem(at: result) }
        try assertSanitized(result)
    }

    func testInvalidPayloadsAreNotAcceptedAsInvoices() throws {
        XCTAssertThrowsError(try IncomingInvoiceImage.copy(data: Data()))
        XCTAssertThrowsError(try IncomingInvoiceImage.copy(data: Data("not an image".utf8)))
    }

    func testLegacyPublicImageItemAcceptsEncodedData() async throws {
        let bytes = try encoded(.jpeg)
        let provider = NSItemProvider(item: bytes as NSData, typeIdentifier: UTType.image.identifier)
        let result = try await SharedInvoiceLoader.load(from: provider)
        defer { try? FileManager.default.removeItem(at: result) }
        try assertSanitized(result)
    }

    func testBMPAndGIFAreConvertedToReadableStillImages() throws {
        for type in [UTType.bmp, .gif] {
            let result = try IncomingInvoiceImage.copy(data: encoded(type))
            defer { try? FileManager.default.removeItem(at: result) }
            XCTAssertEqual(try EvidenceFiles.imageExtension(result), "jpg")
        }
    }

    func testAnimatedGIFFirstFrameCanBeImportedAsInvoice() throws {
        let data = NSMutableData()
        let input = try XCTUnwrap(CGImageSourceCreateWithData(encoded(.png) as CFData, nil))
        let frame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(input, 0, nil))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(destination, frame, nil); CGImageDestinationAddImage(destination, frame, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try IncomingInvoiceImage.copy(data: data as Data)
        defer { try? FileManager.default.removeItem(at: result) }
        XCTAssertEqual(try EvidenceFiles.imageExtension(result), "jpg")
        let normalized = try XCTUnwrap(CGImageSourceCreateWithURL(result as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(normalized), 1)
    }

    private func assertSanitized(_ url: URL) throws {
        XCTAssertEqual(try EvidenceFiles.imageExtension(url), "jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let p = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(p[kCGImagePropertyGPSDictionary]); XCTAssertNil(p[kCGImagePropertyIPTCDictionary])
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
    }
    private func encoded(_ type: UTType) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1032, height: 733, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1032, height: 733))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [kCGImagePropertyOrientation: 6, kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 10.7, kCGImagePropertyGPSLatitudeRef: "N"], kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:14 10:00:00"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
