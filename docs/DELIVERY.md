# Sweep 0.2.0 — Sổ giao hàng

## Nhận đơn

1. Tab **Đơn hàng → Nhận đơn**. Chọn/chụp phiếu nội bộ có tiền; nhập mã phiếu duy nhất, tên khách và tổng VND. Kiểm lại ảnh lớn trước khi lưu.
2. Nếu đã ký phiếu nhận việc, bật **Đã ký nhận phiếu để đi giao** và chọn đúng ngày ký. Đây là chữ ký của người nhận việc, không phải chữ ký khách.
3. Chưa ký: lưu đơn nháp. Sau này vào chi tiết → xác nhận ký nhận. Mỗi hồ sơ chỉ có một lượt tính công, mặc định 5.000₫; giao lại không tự thêm công.

Mã phiếu trùng hoặc mã gói Bill đã nhập sẽ mở hồ sơ cũ, không ghi đè khoản thu. Ảnh nội bộ giống hệt một hồ sơ cũ bị chặn để kiểm tra; chỉ xác nhận dùng lại ảnh khi đó là phiếu khác hợp lệ. Một khách có hai phiếu khác nhau vẫn là hai hồ sơ.

## Nhập Bill 3.2.0

- Chọn **Nhập Bill → Chọn thư mục Bill**.
- Trong Tệp, chọn `iCloud Drive/Shortcuts/SenTechTips_AnhDonHang`. Bên trong cần có `Ảnh Đơn Hàng`, `Đơn mới`, và/hoặc `orders.json`.
- Nếu ảnh/JSON chỉ có trên iCloud, tải thư mục về bằng Tệp trước. Sweep giữ quyền đọc trong phiên nhập; chọn lại thư mục khi mở lại app.
- Mở từng hồ sơ xem trước, đối chiếu tổng và khoản thu cũ, nhập mã phiếu thực tế rồi lưu. Không tự đánh dấu mọi đơn cũ là đã ký trong tháng hiện tại.
- Sổ cũ thiếu ảnh, schema khác hoặc tiền không hợp lệ sẽ hiện lỗi/cảnh báo. Ảnh cũ nằm trong thư mục riêng ngoài thư mục đã chọn chưa được dò tự động. Dữ liệu Bill không bị sửa, dọn hoặc ghi ngược.
- Sau khi chuyển sang dùng Sweep, chốt tiền ở Sweep. Hai sổ không đồng bộ hai chiều; không dùng cả hai để sửa cùng một đơn rồi kỳ vọng tự hợp nhất.

## Chốt giao / thu tiền

Trong chi tiết đơn, nút dưới cùng mở **Chốt giao / thu tiền**. Kết quả giao và hình thức thanh toán là hai trường độc lập. Nhập giá trị **tổng thực tế đã nhận của đơn**, không phải số tiền cần cộng thêm vào lần trước.

| Tình huống | Tiền và ảnh |
| --- | --- |
| Tiền mặt | Ghi thực thu; chuyển khoản bằng 0 |
| CK ngay | Ghi số tiền khách báo; thêm ảnh giao dịch; chỉ xác nhận đối soát khi công ty xác nhận |
| CK sau | Hai khoản bằng 0; thêm phiếu khách ký; chưa ghi thành đã chuyển |
| Hỗn hợp | Ghi riêng CK và tiền mặt; thêm phiếu khách ký và giao dịch |
| Giao thất bại/hoãn | Ghi lý do; giữ đúng số đã nhận; công ký nhận vẫn giữ |

Ví dụ tổng 2.165.000₫, CK 1.500.000₫ và tiền mặt 600.000₫: còn 65.000₫ theo ghi nhận. CK vẫn chờ đối soát nếu công ty chưa xác nhận. Nhập vượt tổng đơn bị chặn; chưa hỗ trợ xử lý tiền thừa.

Sửa lần chốt tạo bản ghi mới, giữ lịch sử cũ; cần kiểm tra đối soát CK và báo cáo lại. Hủy chia sẻ không hủy khoản thu đã lưu.

## Chứng từ và báo cáo

- Bổ sung nhiều ảnh theo vai trò: phiếu nội bộ / phiếu khách ký / ảnh giao dịch. Chạm ảnh để xem đầy đủ. Ảnh đã nhập được giữ riêng, không phụ thuộc ảnh gốc còn trong Photos.
- Chọn nhầm ảnh: nhấn giữ ảnh → Loại khỏi bộ báo cáo, ghi lý do rồi thêm ảnh đúng. Ảnh cũ và bộ báo cáo trước được giữ trong lịch sử, không thêm công đơn.
- Mở **Chuẩn bị và chia sẻ báo cáo**, kiểm nội dung và thứ tự ảnh, bấm kiểm tra/chuẩn bị.
- Thiếu ảnh bắt buộc vẫn giữ được chốt tiền, nhưng chưa chuẩn bị báo cáo hoàn chỉnh.
- Có nút Lưu nội dung nháp để giữ phần đang soạn khi chưa đủ ảnh; lưu nháp không xác nhận đã gửi.
- Chia sẻ nội dung + ảnh bằng iOS; chọn nhóm Zalo thủ công. Nếu ứng dụng đích bỏ nội dung, dùng **Sao chép nội dung** và **Chỉ chia sẻ bộ ảnh**.
- Quay lại bấm **Tôi đã gửi báo cáo…** sau khi thực sự gửi đủ. Mở/đóng bảng chia sẻ không tự xác nhận gửi.
- Zalo trên máy thật cần được thử riêng; kiểm thử simulator không chứng minh tin được gửi vào nhóm.

## Đối soát

- **Công** lọc theo tháng ký nhận, dùng mức công lưu lúc ký. CSV chứa toàn bộ phiếu hợp lệ trong tháng. Nhập số kế toán để xem chênh; danh sách mã phiếu là cơ sở kiểm tra.
- **Tiền mặt** hiển thị toàn sổ: đã thu − những lần nộp hợp lệ = còn giữ. Tiền công không bị tự trừ.
- Chỉ ghi nộp sau khi đã nộp thật. Nếu nhập nhầm, vào lịch sử nộp → điều chỉnh có lý do. Bản ghi gốc không bị xóa; thao tác này không chuyển tiền ngoài app.
- CK chờ đối soát có danh sách riêng. Ảnh giao dịch của khách chưa tự xác nhận công ty nhận tiền.
- Hủy hồ sơ nhập nhầm cần lý do và không còn khoản thu; giữ lịch sử điều chỉnh công. Chưa có chức năng tạo thêm công cho lượt tái giao trong cùng một hồ sơ.

## Cấu hình và sao lưu

Trong **Cài đặt → Công đơn và QR công ty**, nhập thông tin công ty và chọn ảnh QR chính xác. Khách xem màn hình QR từ chi tiết đơn.

Trong **Sao lưu và khôi phục**, xuất `.sweepbackup` rồi chọn Lưu vào Tệp. Bản sao chứa sổ và toàn bộ ảnh, không chỉ liên kết iCloud. Giữ bản sao trước khi xóa app, đổi máy hoặc cài lại. Cập nhật qua AltStore cùng app ID thông thường giữ container; không gỡ app để cập nhật.

Khôi phục kiểm tra schema, đường dẫn và hash tất cả ảnh trước khi thay sổ. Có xác nhận thay toàn bộ, không gộp. App giữ bản trước khôi phục trên máy, có nút xuất lại trong trang sao lưu. Việc mở bảng chia sẻ chưa chứng minh bản sao đã được lưu vào Tệp.

OCR native, tự đọc nhóm Zalo, Share Extension, đồng bộ trực tiếp iCloud và nghiệp vụ hoàn tiền/tiền thừa chưa nằm trong 0.2.0. Các công cụ ảnh 0.1.0 vẫn ở tab Công cụ.
