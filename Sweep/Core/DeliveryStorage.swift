import Foundation
import SQLite3
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum DeliveryCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}

/// The ledger and its immutable business events commit together. Never replace a corrupt store with an empty one.
final class DeliveryDatabase {
    private var connection: OpaquePointer?
    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if connection != nil { sqlite3_close(connection); connection = nil }
            throw DeliveryError.invalid("Không mở được sổ dữ liệu.")
        }
        do {
            try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000;")
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else { throw failure() }
            let version = sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : -1
            sqlite3_finalize(statement)
            guard version == 0 || version == 1 else { throw DeliveryError.invalid("Sổ được tạo bởi Sweep mới hơn. Giữ dữ liệu và cập nhật app.") }
            try execute("CREATE TABLE IF NOT EXISTS ledger (id INTEGER PRIMARY KEY CHECK(id IN (1,2)), payload BLOB NOT NULL); PRAGMA user_version=1;")
        } catch { sqlite3_close(connection); connection = nil; throw error }
    }
    deinit { sqlite3_close(connection) }
    private func failure() -> DeliveryError { .invalid("Không ghi/đọc được sổ: " + String(cString: sqlite3_errmsg(connection))) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    func load() throws -> DeliveryLedger {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "SELECT payload FROM ledger WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return DeliveryLedger() }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure() }
        let ledger = try DeliveryCoding.decode(DeliveryLedger.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
        try ledger.validate(); return ledger
    }
    func save(_ ledger: DeliveryLedger, replacing: Bool = false) throws {
        try ledger.validate()
        let data = try DeliveryCoding.encode(ledger)
        guard data.count <= 32 * 1024 * 1024 else { throw DeliveryError.invalid("Sổ vượt giới hạn 32 MB dữ liệu mô tả. Ảnh được lưu riêng; giữ sổ hiện tại và xuất sao lưu trước khi nâng phiên bản.") }
        try execute("BEGIN IMMEDIATE")
        do {
            if !replacing { try ledger.validateAppendOnly(from: load()) }
            try execute("INSERT OR REPLACE INTO ledger(id,payload) SELECT 2,payload FROM ledger WHERE id=1")
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, "INSERT OR REPLACE INTO ledger(id,payload) VALUES(1,?)", -1, &statement, nil) == SQLITE_OK else { throw failure() }
            defer { sqlite3_finalize(statement) }
            let result = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
}

enum EvidenceFiles {
    static let maximumBytes: Int64 = 80 * 1024 * 1024
    static func hash(_ url: URL) throws -> (String, Int64) {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var digest = SHA256(); var count: Int64 = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            count += Int64(data.count)
            guard count <= maximumBytes else { throw DeliveryError.invalid("Mỗi ảnh chứng từ tối đa 80 MB.") }
            digest.update(data: data)
        }
        guard count > 0 else { throw DeliveryError.invalid("Ảnh chưa có dữ liệu. Tải ảnh từ iCloud rồi thử lại.") }
        return (digest.finalize().map { String(format: "%02x", $0) }.joined(), count)
    }
    static func imageExtension(_ url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0, let identifier = CGImageSourceGetType(source) as String?, let type = UTType(identifier) else {
            throw DeliveryError.invalid("Dữ liệu nguồn chưa phải ảnh giải mã được; có thể nguồn chia sẻ cung cấp một dạng khác với tệp gốc.")
        }
        let formats: [(UTType, String)] = [(.jpeg, "jpg"), (.png, "png"), (.heic, "heic"), (.heif, "heif")]
        guard let ext = formats.first(where: { type.conforms(to: $0.0) })?.1 else { throw DeliveryError.invalid("Dạng ảnh nhận được là \(identifier); cần chuẩn hóa trước khi lưu.") }
        if type.conforms(to: .png), CGImageSourceGetCount(source) > 1 { throw DeliveryError.invalid("Ảnh PNG động chưa được nhận làm phiếu. Chọn ảnh tĩnh.") }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let w = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
              let h = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value, w > 0, h > 0 else { throw DeliveryError.invalid("Chưa đọc được kích thước ảnh nguồn.") }
        guard w <= 120_000_000 / h else { throw DeliveryError.invalid("Ảnh nguồn vượt 120 megapixel.") }
        guard CGImageSourceCreateThumbnailAtIndex(source, index, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else { throw DeliveryError.invalid("Không giải mã được ảnh \(identifier) kích thước \(w)×\(h).") }
        return ext
    }
    static func importImage(_ source: URL, role: EvidenceRole, directory: URL) throws -> DeliveryEvidence {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        var coordination: NSError?; var captured: Error?; var output: DeliveryEvidence?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordination) { url in
            do {
                let (hash, bytes) = try self.hash(url)
                let ext = try imageExtension(url)
                let target = directory.appendingPathComponent(UUID().uuidString + "." + ext)
                do {
                    try FileManager.default.copyItem(at: url, to: target)
                    let copied = try self.hash(target)
                    guard copied.0 == hash, copied.1 == bytes else { throw DeliveryError.invalid("Ảnh sao chép chưa đủ. Chưa lưu hồ sơ.") }
                    output = DeliveryEvidence(role: role, filename: target.lastPathComponent, sha256: hash, bytes: bytes)
                } catch { try? FileManager.default.removeItem(at: target); throw error }
            } catch { captured = error }
        }
        if let error = coordination as Error? ?? captured { throw error }
        guard let output else { throw DeliveryError.invalid("Không đọc được ảnh đã chọn.") }
        return output
    }
    static func verify(_ file: DeliveryEvidence, directory: URL) throws {
        let result = try hash(directory.appendingPathComponent(file.filename))
        guard result.0 == file.sha256, result.1 == file.bytes else { throw DeliveryError.invalid("Ảnh chứng từ bị thiếu hoặc sai hash. Không hoàn tất thao tác.") }
    }
}

/// Streaming, versioned archive: magic, manifest length, manifest SHA256, manifest, original image bytes.
/// No decoding of arbitrary paths, no ZIP expansion and no unbounded allocation for image payloads.
enum DeliveryBackup {
    struct Manifest: Codable { var version = 1; var createdAt = Date(); var ledger: DeliveryLedger }
    final class Prepared: @unchecked Sendable {
        let ledger: DeliveryLedger
        let staging: URL
        init(ledger: DeliveryLedger, staging: URL) { self.ledger = ledger; self.staging = staging }
        deinit { try? FileManager.default.removeItem(at: staging) }
    }
    static let magic = Data("SWEEP001".utf8)
    static func write(_ ledger: DeliveryLedger, evidence: URL, to destination: URL) throws {
        try ledger.validate()
        let manifest = try DeliveryCoding.encode(Manifest(ledger: ledger))
        guard manifest.count <= 32 * 1024 * 1024 else { throw DeliveryError.invalid("Sổ quá lớn cho định dạng sao lưu này.") }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        do {
            try handle.write(contentsOf: magic)
            var length = UInt64(manifest.count).bigEndian
            try withUnsafeBytes(of: &length) { try handle.write(contentsOf: Data($0)) }
            try handle.write(contentsOf: Data(SHA256.hash(data: manifest)))
            try handle.write(contentsOf: manifest)
            for file in ledger.allEvidence {
                let reader = try FileHandle(forReadingFrom: evidence.appendingPathComponent(file.filename))
                defer { try? reader.close() }
                var hash = SHA256(); var bytes: Int64 = 0
                while let data = try reader.read(upToCount: 1024 * 1024), !data.isEmpty {
                    bytes += Int64(data.count)
                    guard bytes <= file.bytes else { throw DeliveryError.invalid("Ảnh nguồn đã đổi kích thước.") }
                    hash.update(data: data); try handle.write(contentsOf: data)
                }
                guard bytes == file.bytes, hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else { throw DeliveryError.invalid("Ảnh nguồn thiếu hoặc sai hash. Chưa tạo bản sao lưu.") }
            }
            try handle.synchronize(); try handle.close()
        } catch { try? handle.close(); try? FileManager.default.removeItem(at: destination); throw error }
    }
    private static func read(_ count: Int, from handle: FileHandle) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let chunk = try handle.read(upToCount: count - data.count), !chunk.isEmpty else { throw DeliveryError.invalid("Bản sao lưu bị thiếu dữ liệu.") }
            data.append(chunk)
        }
        return data
    }
    static func prepare(_ source: URL, staging: URL) throws -> Prepared {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
            guard try read(8, from: handle) == magic else { throw DeliveryError.invalid("Tệp không phải bản sao lưu Sweep.") }
            let lengthData = try read(8, from: handle)
            let length = lengthData.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            guard length > 0 && length <= 32 * 1024 * 1024 else { throw DeliveryError.invalid("Độ dài dữ liệu sao lưu không hợp lệ.") }
            let expected = try read(32, from: handle), data = try read(Int(length), from: handle)
            guard Data(SHA256.hash(data: data)) == expected else { throw DeliveryError.invalid("Thông tin sổ bị sai hash.") }
            let manifest = try DeliveryCoding.decode(Manifest.self, from: data)
            guard manifest.version == 1 else { throw DeliveryError.invalid("Bản sao lưu cần phiên bản Sweep mới hơn.") }
            try manifest.ledger.validate()
            for file in manifest.ledger.allEvidence {
                let target = staging.appendingPathComponent(file.filename)
                FileManager.default.createFile(atPath: target.path, contents: nil)
                let writer = try FileHandle(forWritingTo: target); defer { try? writer.close() }
                var remaining = file.bytes; var hash = SHA256()
                while remaining > 0 {
                    let chunk = try read(Int(min(remaining, 1024 * 1024)), from: handle)
                    remaining -= Int64(chunk.count); hash.update(data: chunk); try writer.write(contentsOf: chunk)
                }
                try writer.synchronize(); try writer.close()
                guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else { throw DeliveryError.invalid("Ảnh trong sao lưu sai hash.") }
                _ = try EvidenceFiles.imageExtension(target)
            }
            guard try handle.read(upToCount: 1)?.isEmpty != false else { throw DeliveryError.invalid("Bản sao lưu có dữ liệu thừa.") }
            return Prepared(ledger: manifest.ledger, staging: staging)
        } catch { try? FileManager.default.removeItem(at: staging); throw error }
    }
}
