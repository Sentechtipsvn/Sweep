# Sweep 0.3.2 — nhận ảnh chia sẻ và tạo lại QR

## Nhận ảnh

Thông báo cũ gộp mọi lỗi đọc ảnh vào “JPEG/PNG/HEIC tối đa 120 MP”, không đủ để xác định vì sao tệp JPEG nhỏ bị từ chối. Ảnh chụp người dùng gửi xác nhận JPEG 1032×733, nhưng không chứa bytes hoặc danh sách representation do Zalo đưa vào NSItemProvider; chưa thể khẳng định representation cụ thể trên máy thật.

- Thử JPEG/PNG/HEIC cụ thể trước kiểu ảnh chung, không chỉ lấy representation đầu tiên.
- Nếu bản tệp không đọc được, thử dữ liệu ảnh, đường dẫn rồi UIImage. Sao chép dữ liệu trước khi callback của nguồn hết hiệu lực.
- JPEG/PNG/HEIC hợp lệ giữ nguyên bytes; representation ảnh tĩnh khác, như TIFF, được chuẩn hóa cục bộ sang PNG tối đa cạnh 3072 px. Không tải ảnh lên máy chủ.
- Đọc ảnh chính và hướng ảnh; JPEG/HEIC có dữ liệu phụ không bị loại chỉ vì số ảnh lớn hơn một. Giữ chặn ảnh động PNG, dữ liệu hỏng, quá 80 MB hoặc quá 120 MP.
- Lỗi cuối hiển thị UTI và cách đọc thất bại để chẩn đoán, không gán mọi trường hợp thành vượt megapixel.

## QR

Ảnh màn hình cho thấy khoản còn lại theo ghi nhận bằng 0; điều kiện trong app đã khóa nút trước khi gọi VietQR. Đây là giới hạn ở UI/model, không phải phản hồi lỗi API.

- Cho tạo/xem lại QR theo số tiền nhập từ 1 đồng đến tổng đơn, kể cả đã ghi nhận đủ tiền hoặc khách đã báo CK nhưng chưa đối soát.
- Mặc định: khoản còn lại, nếu bằng 0 thì khoản CK còn chờ đối soát, sau cùng là tổng đơn. Có thể sửa số tiền.
- Tạo QR không sửa tiền mặt, CK, đối soát, công hoặc trạng thái giao. Hồ sơ đã hủy vẫn không tạo QR.
- Tiếp tục giữ App Group metadata và cơ chế đọc ALTAppGroups của 0.3.1.

## Kiểm tra

Thêm kiểm thử JPEG có metadata/tên tệp chung, Data provider, tệp lỗi rồi fallback Data, ưu tiên JPEG thay TIFF, chuẩn hóa TIFF và từ chối dữ liệu hỏng. Bổ sung QR khi khoản còn lại bằng 0 và khi CK đã đối soát. Fixture simulator nhận UIImage qua cùng loader; thêm UI test QR bằng tài khoản ví dụ công khai của tài liệu VietQR. Không dùng tài khoản thật hoặc ảnh hóa đơn của người dùng trong CI.

Kết quả chỉ được xác nhận sau khi CI hoàn tất. Tệp JPEG gốc trong Zalo và Share Sheet trên iPhone vẫn cần thử lại sau khi cài. Không gỡ app chứa sổ; ký cài đè và giữ tiện ích mở rộng như trước.
