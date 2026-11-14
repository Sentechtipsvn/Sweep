import Foundation
import Vision
import ImageIO

/// Runs locally; no server, photo-library scan or network request.
enum InvoiceOCR {
    static func read(_ url: URL) throws -> InvoiceFields {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else { throw DeliveryError.invalid("Không mở được ảnh để đọc phiếu. Tải bản gốc trong Tệp rồi thử lại.") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        let supported = try request.supportedRecognitionLanguages()
        let preferred = ["vi-VN", "en-US"].filter { supported.contains($0) }
        if !preferred.isEmpty { request.recognitionLanguages = preferred }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let observations = request.results ?? []
        // Preserve two-column label/value rows when Vision returns separate text boxes.
        var rows: [[VNRecognizedTextObservation]] = []
        for observation in observations.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            if let last = rows.last, let anchor = last.first,
               abs(anchor.boundingBox.midY - observation.boundingBox.midY) < min(anchor.boundingBox.height, observation.boundingBox.height) * 0.45 {
                rows[rows.count - 1].append(observation)
            } else { rows.append([observation]) }
        }
        let text = rows.map { row in row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "    ") }.joined(separator: "\n")
        return InvoiceParser.parse(text)
    }
}
