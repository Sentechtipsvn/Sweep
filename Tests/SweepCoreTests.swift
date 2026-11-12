import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SweepCore

final class SweepCoreTests: XCTestCase {
    func testOnlyEligibleMatchingDimensionsAreCandidates() {
        let photos = [photo("a"), photo("b"), photo("live", eligible: false), PhotoRecord(id: "other", width: 2, height: 3)]
        XCTAssertEqual(DuplicateRules.candidateIDs(in: photos), ["a", "b"])
    }
    func testGroupsRequireCompleteDataAndKeepFavoriteFirst() {
        let a = PhotoDigest(photo: photo("a"), hash: "same", bytes: 100)
        let favorite = PhotoDigest(photo: photo("b", favorite: true), hash: "same", bytes: 100)
        let groups = DuplicateRules.groups(from: [a, favorite,
            PhotoDigest(photo: photo("c"), hash: "same", bytes: 200),
            PhotoDigest(photo: photo("empty"), hash: "same", bytes: 0),
            PhotoDigest(photo: photo("live", eligible: false), hash: "same", bytes: 100)])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members.map(\.id), ["b", "a"])
        XCTAssertEqual(groups[0].removableBytes, 100)
        XCTAssertFalse(DuplicateRules.keepsAtLeastOne(in: groups, deleting: ["a", "b"]))
        XCTAssertTrue(DuplicateRules.keepsAtLeastOne(in: groups, deleting: ["a"]))
    }
    func testRepeatedAssetNeverCountsAsDuplicate() {
        let digest = PhotoDigest(photo: photo("a"), hash: "same", bytes: 100)
        XCTAssertTrue(DuplicateRules.groups(from: [digest, digest]).isEmpty)
    }
    func testContainmentRejectsSiblingAndSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("inside".utf8).write(to: root.appendingPathComponent("file"))
        XCTAssertTrue(FileRules.isDescendant(root.appendingPathComponent("file"), of: root))
        XCTAssertFalse(FileRules.isDescendant(root, of: root))
        XCTAssertFalse(FileRules.isDescendant(URL(fileURLWithPath: root.path + "-sibling/file"), of: root))
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.deletingLastPathComponent())
        XCTAssertFalse(FileRules.isDescendant(link.appendingPathComponent("outside"), of: root))
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        XCTAssertFalse(FileRules.isDescendant(link.appendingPathComponent(outside.lastPathComponent), of: root))
    }
    func testEncodingResizesRotatesStripsGPSAndKeepsInput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.jpg"), output = directory.appendingPathComponent("output.jpg")
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 400, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.8, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(input as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 10.7, kCGImagePropertyGPSLatitudeRef: "N"]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let original = try Data(contentsOf: input)
        let result = try ImageEncoder.encode(source: input, destination: output, maxDimension: 320, quality: 0.7)
        XCTAssertEqual(result.width, 160); XCTAssertEqual(result.height, 320)
        XCTAssertGreaterThan(result.outputBytes, 0)
        XCTAssertEqual(try Data(contentsOf: input), original)
        let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil) as? [CFString: Any])
        XCTAssertNil(props[kCGImagePropertyGPSDictionary])
    }
    func testCorruptImageFailsWithoutOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("broken.jpg"), output = root.appendingPathComponent("output.jpg")
        try Data("not an image".utf8).write(to: input)
        XCTAssertThrowsError(try ImageEncoder.encode(source: input, destination: output, maxDimension: 2048, quality: 0.8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    private func photo(_ id: String, favorite: Bool = false, eligible: Bool = true) -> PhotoRecord {
        PhotoRecord(id: id, width: 100, height: 200, favorite: favorite, eligibleForExactMatch: eligible)
    }
}
