import Foundation
import CryptoKit

enum VietQRService {
    /// Derived QR only. The invoice image and customer name/address are never uploaded.
    static func svg(for url: URL) async throws -> Data {
        guard url.scheme == "https", url.host == "img.vietqr.io", url.path.hasSuffix(".svg") else { throw DeliveryError.invalid("Địa chỉ VietQR không hợp lệ.") }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VietQR", isDirectory: true)
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let cached = directory.appendingPathComponent(key + ".svg")
        if let bytes = try? cached.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes <= 2 * 1024 * 1024,
           let data = try? Data(contentsOf: cached), isSVG(data) { return data }
        var request = URLRequest(url: url); request.timeoutInterval = 20
        request.setValue("image/svg+xml", forHTTPHeaderField: "Accept")
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.host == "img.vietqr.io", http.url?.scheme == "https",
              http.mimeType == "image/svg+xml", http.expectedContentLength <= 2 * 1024 * 1024 else {
            throw DeliveryError.invalid("VietQR chưa trả về mã QR. Kiểm tra ngân hàng, số tài khoản và kết nối rồi thử lại.")
        }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < 2 * 1024 * 1024 else { throw DeliveryError.invalid("Ảnh QR vượt giới hạn cho phép.") }
            data.append(byte)
        }
        guard isSVG(data) else { throw DeliveryError.invalid("Dữ liệu trả về chưa phải ảnh QR SVG.") }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cached, options: .atomic)
        return data
    }
    private static func isSVG(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= 2 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("<svg") && text.contains("</svg>")
    }
}
