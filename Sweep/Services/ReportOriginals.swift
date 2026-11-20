import Photos
import UIKit

enum OriginalPhotoPolicy: String, CaseIterable {
    case ask = "Hỏi sau khi gửi", always = "Luôn cho phép", keep = "Luôn giữ ảnh"
    static let key = "sendeli.report.originals.policy"
}

/// Device-local provenance only. Imported backups cannot supply Photos deletion targets.
@MainActor enum ReportOriginals {
    private static func key(_ file: DeliveryEvidence) -> String? {
        guard let device = UIDevice.current.identifierForVendor else { return nil }
        return "sendeli.photo.\(device.uuidString).\(file.id.uuidString).\(file.sha256)"
    }
    static func remember(_ asset: String?, file: DeliveryEvidence) {
        guard let asset, !asset.isEmpty, let key = key(file) else { return }
        UserDefaults.standard.set(asset, forKey: key)
    }
    static func candidates(_ files: [DeliveryEvidence]) -> [String: String] {
        var result: [String: String] = [:]
        for file in files {
            if let key = key(file), let asset = UserDefaults.standard.string(forKey: key) { result[key] = asset }
        }
        return result
    }
    static func delete(_ references: [String: String]) async throws {
        guard !references.isEmpty else { return }
        let auth = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard auth == .authorized || auth == .limited else { throw DeliveryError.invalid("Đã gửi báo cáo. Sendeli chưa có quyền xoá ảnh gốc.") }
        let wanted = Set(references.values)
        let accessible = PHAsset.fetchAssets(withLocalIdentifiers: Array(wanted), options: nil)
        var ids = Set<String>()
        accessible.enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        if !ids.isEmpty { try await PhotoLibraryService.delete(ids: ids) }
        for (key, asset) in references where ids.contains(asset) || auth == .authorized {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if auth == .limited && ids != wanted { throw DeliveryError.invalid("Đã gửi báo cáo. Một số ảnh gốc nằm ngoài quyền truy cập giới hạn.") }
    }
}
