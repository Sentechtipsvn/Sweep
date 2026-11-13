# Sweep

**Sổ giao hàng và công cụ ảnh trên iPhone.** · © Sentechtipsvn

Bản thử nghiệm **0.2.1 (3)**, yêu cầu **iOS 17.0 trở lên**. Máy đích: iPhone 11/iOS 18.7.8. Công cụ nén và danh sách ảnh của 0.1.0 đã được chủ dự án thử trên iPhone; các luồng giao hàng mới cần thử tiếp trên thiết bị. Không cần LocalDevVPN, tài khoản hoặc máy chủ của Sweep.

## Sổ giao hàng 0.2.1

- Bốn tab: Đơn hàng / Đối soát / Công cụ / Cài đặt; bỏ banner lớn, giữ bốn công cụ ảnh cũ.
- Nhập phiếu từ Ảnh, Tệp hoặc camera; tên, mã phiếu duy nhất, tổng VND, điện thoại và địa chỉ được OCR Vision gợi ý ngay trên máy, Sếp kiểm tra trước khi nhập. Ảnh sao chép riêng, kiểm tra hash trước khi hoàn tất. Có nháp chưa tính công.
- Nhập đọc-only thư mục Bill 3.2.0/3.3.0 `SenTechTips_AnhDonHang`: nhận `sen-bill-v1` và `sen-orders-v3` có bản ghi JSON hoặc chuỗi JSON. Xem trước từng hồ sơ, giữ khoản tiền cũ, không tự lấy ngày giao làm ngày ký. Lưu bản metadata nguồn và ngày lưu bên Bill. Video máy thật đã xác nhận tìm thấy 14 hồ sơ trong sổ cũ. Bản 0.2.1 bổ sung nút nhập luôn thấy, OCR các ảnh cũ và thông tin đầu phiếu từ Bill 3.3.0; cần thử lại bước lưu trên máy thật.
- Mỗi hồ sơ có đúng một lượt ký nhận đi giao, mặc định 5.000₫; ngày ký tách ngày nhập/ngày hóa đơn/ngày chốt. Giao thất bại, CK sau và báo cáo lại không đổi công. Đổi mức công chỉ áp dụng lượt ký mới.
- Chốt tiền mặt / CK / CK sau / hỗn hợp; nhập số thực tế, kiểm tra khoản thừa, giữ tiền khi đổi kết quả giao. CK khách báo tách CK công ty xác nhận; sửa lần chốt cần đối soát lại.
- Lưu nhiều ảnh theo vai trò phiếu nội bộ / phiếu khách ký / giao dịch. Báo cáo kiểm tra đủ chứng từ, cho sửa nội dung và xem thứ tự ảnh. Chia sẻ iOS, có nút sao chép và chia sẻ riêng ảnh. Chỉ xác nhận đã gửi bằng nút riêng; sửa hồ sơ làm báo cáo cần gửi lại.
- Công theo tháng ký, so với số kế toán, CSV toàn bộ phiếu; tiền mặt toàn sổ và nộp tiền riêng. Hủy hồ sơ nhập nhầm và điều chỉnh lần nộp nhầm giữ sự kiện gốc, lý do và lịch sử.
- QR/tài khoản công ty do người dùng cấu hình. Gọi và Apple Maps từ thông tin người dùng nhập, không đoán số/địa chỉ.
- SQLite giao dịch nguyên tử, lịch sử tiền/công chỉ bổ sung. Sao lưu `.sweepbackup` gồm sổ và ảnh gốc, ghi/đọc theo luồng và kiểm tra SHA-256. Khôi phục kiểm tra toàn bộ trước, giữ bản trước khôi phục và chỉ thay sổ khi hoàn tất.

Xem [hướng dẫn giao hàng](docs/DELIVERY.md), [kiến trúc dữ liệu](docs/DELIVERY-ARCHITECTURE.md) và [điểm cần thử trên iPhone](docs/TESTING.md).

Xem [thay đổi 0.2.1](docs/RELEASE-0.2.1.md) và [giao thức Bill](Integrations/Bill/README.md).

## Công cụ ảnh giữ từ 0.1.0

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
- Chưa có nhận đơn tự động từ Zalo, Share Extension, đồng bộ hai chiều với Bill, nén video, quét gia tăng, chạy nền dài hoặc dọn qua pairing. Không dọn cache app khác/Dữ liệu hệ thống.

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

Kiểm thử mới bao gồm công theo ngày ký, chống lặp, tiền thực tế, đối soát CK, lịch sử bất biến, SQLite mở lại, nhập schema Bill, CSV, sao lưu/ảnh lỗi và điều hướng trên simulator. Các bài kiểm thử công cụ ảnh: nhóm trùng theo hash/byte, bỏ tài nguyên không hỗ trợ, gợi ý giữ ảnh yêu thích, ngăn xóa hết nhóm, không đếm lặp ID, đường dẫn/symlink thoát thư mục, ảnh nén đúng kích thước/chiều xoay/bỏ GPS/giữ đầu vào và từ chối tệp lỗi. Chúng không thay thế kiểm thử PhotoKit/quyền/xóa/iCloud trên iPhone.

Xem [kịch bản thử trên iPhone](docs/TESTING.md) trước khi dùng trên dữ liệu quan trọng.

## Phạm vi mã nguồn

Sweep được dựng mới; không sao chép mã nguồn StikDebug hoặc Tetherless. Việc tái sử dụng thư viện sau này cần kiểm tra giấy phép riêng. Chủ repo chưa chọn giấy phép phát hành mã nguồn cho Sweep.
