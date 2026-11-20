import Foundation

enum BackupPart: String, CaseIterable, Codable {
    case orders, photos, places, contacts, payroll
    static let all = Set(allCases)
    var title: String {
        switch self {
        case .orders: return "Đơn hàng, tiền và cấu hình"
        case .photos: return "Ảnh chứng từ và QR"
        case .places: return "Vị trí đã lưu"
        case .contacts: return "Danh bạ"
        case .payroll: return "Chấm công và lương"
        }
    }
    static func check(_ selection: Set<Self>) throws {
        guard !selection.isEmpty, !selection.contains(.orders) || selection.contains(.photos) else {
            throw DeliveryError.invalid("Đơn đã ký và báo cáo cần ảnh chứng từ đi kèm.")
        }
    }
}

struct ArchivedPhoto: Codable, Equatable {
    var orderID: UUID?
    var evidence: DeliveryEvidence
    var excluded: Bool? = nil
}

extension DeliveryLedger {
    var photoIndex: [ArchivedPhoto] {
        orders.flatMap { order in
            let excluded = Set(order.exclusions.map(\.evidenceID))
            return order.evidence.map { ArchivedPhoto(orderID: order.id, evidence: $0, excluded: excluded.contains($0.id) ? true : nil) }
        }
            + (settings.qr.map { [ArchivedPhoto(orderID: nil, evidence: $0)] } ?? []) + (unfiledPhotos ?? [])
    }
    func selectedBackup(_ parts: Set<BackupPart>) throws -> DeliveryLedger {
        try BackupPart.check(parts)
        if parts == BackupPart.all { return self }
        var subset = parts.contains(.orders) ? self : DeliveryLedger()
        subset.places = parts.contains(.places) ? places : nil
        subset.contacts = parts.contains(.contacts) ? contacts : nil
        subset.payroll = parts.contains(.payroll) ? payroll : nil
        if !parts.contains(.orders) && parts.contains(.photos) { subset.unfiledPhotos = photoIndex }
        if parts.contains(.orders) {
            // Free-form audit details may contain contact, location or salary data.
            subset.audit = audit.filter { $0.orderID != nil }
        }
        return subset
    }

    func restoring(_ source: DeliveryLedger, parts: Set<BackupPart>) throws -> DeliveryLedger {
        try BackupPart.check(parts)
        if parts == BackupPart.all { return source }
        var next = self
        if parts.contains(.orders) {
            next.orders = source.orders; next.handovers = source.handovers
            next.handoverReversals = source.handoverReversals; next.settings = source.settings
            next.audit = audit.filter { $0.orderID == nil } + source.audit.filter { $0.orderID != nil }
            next.unfiledPhotos = source.unfiledPhotos
        } else if parts.contains(.photos) {
            var existing = Dictionary(uniqueKeysWithValues: next.allEvidence.map { ($0.id, $0) })
            let owners = Dictionary(uniqueKeysWithValues: next.orders.indices.map { (next.orders[$0].id, $0) })
            for photo in source.photoIndex {
                let file = photo.evidence
                if let same = existing[file.id] {
                    guard same == file else { throw DeliveryError.invalid("ID ảnh trùng với chứng từ khác trên máy.") }
                    continue
                }
                if photo.excluded != true, let owner = photo.orderID, let index = owners[owner] {
                    next.orders[index].evidence.append(file)
                    next.orders[index].revision += 1
                } else {
                    if next.unfiledPhotos == nil { next.unfiledPhotos = [] }
                    next.unfiledPhotos?.append(photo)
                }
                existing[file.id] = file
            }
        }
        if parts.contains(.places) { next.places = source.places }
        if parts.contains(.contacts) { next.contacts = source.contacts }
        if parts.contains(.payroll) { next.payroll = source.payroll }
        try next.validate()
        return next
    }
}
