# Sweep 0.3.0 — nhận ảnh chia sẻ và VietQR theo đơn

## Nhận đơn trực tiếp

- Trong Zalo, mở ảnh phiếu → bảng chia sẻ iOS → Sweep → Gửi đến Sweep. Bản đầu nhận một ảnh tĩnh JPEG/PNG/HEIC mỗi lượt; Sweep hiện trong danh sách ứng dụng ở bảng chia sẻ hệ thống, không phải menu chuyển tiếp nội bộ Zalo.
- Ảnh được sao chép vào hộp thư trên thiết bị, không cần Bill hoặc iCloud. Mở Sweep sẽ tự hiện màn hình nhận đơn và OCR khi có một ảnh chờ. Có nhiều ảnh thì chọn phiếu trong hộp thư.
- Kiểm tra mã phiếu, khách và số tiền rồi nhập bằng màn hình đang có. Hủy màn hình không xóa ảnh chờ. Chỉ sau khi lưu sổ thành công mới xóa bản chờ; nguồn Zalo giữ nguyên. Chưa xác nhận ký nhận thì chưa tính công.
- Mã phiếu trùng cần xác nhận là hồ sơ cũ trước khi bỏ ảnh chờ; không tự ghi đè hoặc tạo thêm công. Kho Bill, ảnh/Tệp/camera, đối soát, sao lưu và công cụ ảnh cũ vẫn giữ.
- Không ép mở app chính từ Share Extension bằng API riêng. iOS chạy giao diện nhận ảnh trong bảng chia sẻ; Sếp mở Sweep để kiểm tra và làm các bước giao hàng.

## VietQR

- Cài đặt → Công đơn và QR công ty: nhập mã ngân hàng/BIN, số tài khoản và chủ tài khoản, lưu một lần.
- Chi tiết đơn → QR chuyển khoản: mặc định tổng đơn khi chưa thu, hoặc khoản còn lại theo ghi nhận sau khi đã thu một phần. Có thể sửa số tiền từ 1 đồng đến khoản còn lại. Đơn đã ghi nhận đủ hoặc đã hủy không tạo QR thu thêm.
- Nội dung `TT DON <mã phiếu>` được bỏ dấu, bỏ ký tự đặc biệt và giới hạn 50 ký tự. Số tài khoản giữ số 0 đầu; amount gửi là số nguyên VND.
- Dùng Quick Link `https://img.vietqr.io/image/<BANK>-<ACCOUNT>-qr_only.svg` với `amount`, `addInfo`, `accountName`. Không dùng endpoint `/v2/generate` ngừng hỗ trợ từ 01/01/2027 theo thông báo chính thức.
- SVG hiển thị trong app bằng tài liệu cục bộ không JavaScript, không mở Safari. Cache theo toàn bộ tham số, không dùng mã của số tiền/tài khoản cũ khi sửa. Tạo mã mới cần mạng; cache có thể bị iOS dọn.
- VietQR nhận thông tin tài khoản, tên chủ tài khoản, mã phiếu và số tiền. Không gửi ảnh phiếu, tên khách hoặc địa chỉ. Tên chủ tài khoản do người dùng nhập, không tự tra cứu xác minh.
- Tạo/xem QR không ghi nhận tiền, xác nhận chuyển khoản hay đối soát. Sổ/backup cũ thiếu cấu hình VietQR vẫn đọc được; ảnh QR cố định cũ vẫn ở Cài đặt.

## Cài đặt và ký

IPA chứa `PlugIns/SweepShare.appex`. Cả app `com.sentechtipsvn.sweep` và extension `com.sentechtipsvn.sweep.share` cần được ký và có cùng App Group `group.com.sentechtipsvn.sweep`. Có thể đổi group bằng build setting `SWEEP_APP_GROUP` nhưng phải thống nhất cả hai provisioning profiles và entitlements. Bản ký lại làm mất quyền App Groups hoặc bỏ extension sẽ không nhận ảnh; app báo lỗi cụ thể, không thông báo đã lưu giả.

Không chuyển sổ đang dùng sang container mới: SQLite, ảnh chứng từ và bộ sao lưu hiện tại vẫn ở nơi cũ. App Group chỉ chứa ảnh chờ. Ký lại phải giữ bundle ID để cập nhật app đang có; xuất sao lưu sổ và ảnh trước khi thay bản cài. Không gỡ app chứa sổ thật.

## Phạm vi kiểm chứng

Đã bổ sung test logic URL/số tiền, tương thích dữ liệu cũ, inbox sống qua lần mở mới, dữ liệu lỗi không che mục tốt; đồng thời cấu hình CI build cả app/extension và thao tác nhập OCR trên simulator. Các test Swift/Xcode và simulator chưa chạy: môi trường hiện tại không có Apple SDK, và bước đưa mã lên GitHub đang chờ chủ dự án cho phép. Test fixture dùng inbox riêng, không chứng minh được provisioning thật hay menu Zalo trên iPhone.

Đã kiểm tra tại môi trường soạn mã: cú pháp 37 tệp Swift bằng parser, cấu trúc plist/YAML và whitespace. Đã gọi Quick Link SVG bằng tài khoản ví dụ công khai trong tài liệu VietQR, nhận HTTP 200, render ảnh và giải mã QR để đối chiếu đúng BIN 970415, tài khoản ví dụ 113366668888, số tiền 790000 và nội dung TT DON 3877. Không dùng dữ liệu tài khoản của chủ dự án và không thực hiện chuyển tiền. Parser không thay thế type-check/build Swift.

Cần thử trên iPhone với bản ký giữ App Groups: Zalo → Sweep khi app bị đóng và khi app đang mở, hủy rồi nhận lại, khởi động lại app, mã trùng, hết dung lượng, offline; quét QR bằng app ngân hàng thứ hai để đối chiếu tài khoản/số tiền/nội dung, chỉ kiểm tra thông tin trước bước xác nhận chuyển tiền.

Tài liệu: [Apple Share Extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html), [Apple App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups), [VietQR Quick Link](https://www.vietqr.io/qr-dong), [Thông báo API](https://www.vietqr.io/thong-bao-cap-nhat).
