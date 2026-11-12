# Sweep

**Ảnh gọn. Bộ nhớ thoáng.** · © Sentechtipsvn

Ứng dụng iPhone/iPad xử lý ảnh và kiểm tra dung lượng trên thiết bị. Bản thử nghiệm **0.1.0 (1)**, yêu cầu **iOS 17.0 trở lên**. Máy kiểm thử đích: iPhone 11/iOS 18.7.8. Chưa xác nhận hoạt động trên máy thật cho đến khi chủ dự án cài và thử. Không cần LocalDevVPN hoặc pairing cho những công cụ trong bản này.

## Đã triển khai

- **Ảnh trùng:** SHA-256 dữ liệu gốc, chỉ gom ảnh tĩnh có đúng một tài nguyên gốc. Giới hạn mặc định 500 ảnh gần nhất; chỉnh 100–5.000 trong Cài đặt. Ưu tiên gợi ý giữ ảnh yêu thích, bảo vệ ít nhất một bản mỗi nhóm. Không tự chọn xóa.
- **Ảnh màn hình:** danh sách, xem ảnh lớn, chọn xóa và xác nhận. Xóa bằng PhotoKit.
- **Nén ảnh:** nhập từ Photos hoặc Files; JPEG mới ở cạnh dài 1280/2048/4096, chất lượng tùy chỉnh. Sửa chiều xoay, xem trước/so sánh, lưu bản mới hoặc chia sẻ; giữ nguyên đầu vào. Chỉ xử lý từng ảnh trong bản này.
- **File lớn:** quét thư mục được chọn, giới hạn 20.000 mục, hiển thị tối đa 200 file lớn nhất có sẵn trên máy, xem trước bằng Quick Look. Chưa xóa tài liệu từ Sweep.
- SwiftUI hỗ trợ Light/Dark Mode, iPhone/iPad và xoay màn hình. Không có SDK quảng cáo/phân tích, tài khoản hoặc máy chủ ảnh của Sweep.

## Giới hạn cần biết

- Chỉ quét ảnh được cấp quyền và phạm vi đã chọn. Ảnh ẩn không được đưa vào danh sách mặc định.
- Chưa tìm ảnh gần giống. Live Photos, RAW và ảnh đã chỉnh sửa/nhiều tài nguyên được bỏ qua khi đối chiếu trùng để tránh kết luận từ một phần tài nguyên.
- Đọc ảnh gốc trên iCloud cần tải mạng. Mặc định tắt tải khi quét; chỉ báo kết quả phần đã đọc thành công. Chọn nhập ảnh để nén có thể tải ảnh đó từ iCloud.
- Nén JPEG SDR, không giữ GPS/EXIF, vùng trong suốt thành trắng. Không giữ Live Photo/HDR/RAW hoặc lịch sử chỉnh sửa. Không cam kết đầu ra luôn nhỏ hơn; hiển thị số byte thực tế. Giới hạn đầu vào 80 MB/120 megapixel.
- Ảnh xóa vào Đã xóa gần đây và có thể đồng bộ xóa qua iCloud Photos. Số byte ảnh không đồng nghĩa dung lượng đã giải phóng.
- Chưa có nén video, OCR, Shortcuts, quét gia tăng, chạy nền dài hoặc dọn qua pairing. Không dọn cache app khác/Dữ liệu hệ thống.

## Build và kiểm thử

Máy Mac với Xcode 16.4 và XcodeGen:

```sh
swift test
brew install xcodegen
xcodegen generate
xcodebuild -project Sweep.xcodeproj -scheme Sweep -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

GitHub Actions **Build Sweep IPA** chạy kiểm thử core và build app arm64. Artifact chứa **IPA chưa ký**, cần ký/cài qua công cụ sideload. Chưa tự phát hành lên nguồn AltStore; chỉ thêm sau khi thử trên máy thật.

Các bài kiểm thử: nhóm trùng theo hash/byte, bỏ tài nguyên không hỗ trợ, gợi ý giữ ảnh yêu thích, ngăn xóa hết nhóm, không đếm lặp ID, đường dẫn/symlink thoát thư mục, ảnh nén đúng kích thước/chiều xoay/bỏ GPS/giữ đầu vào và từ chối tệp lỗi. Chúng không thay thế kiểm thử PhotoKit/quyền/xóa/iCloud trên iPhone.

Xem [kịch bản thử trên iPhone](docs/TESTING.md) trước khi dùng trên dữ liệu quan trọng.

## Phạm vi mã nguồn

Sweep được dựng mới; không sao chép mã nguồn StikDebug hoặc Tetherless. Việc tái sử dụng thư viện sau này cần kiểm tra giấy phép riêng. Chủ repo chưa chọn giấy phép phát hành mã nguồn cho Sweep.
