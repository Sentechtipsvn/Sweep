# Sweep 0.2.0 — thử trên iPhone

0.1.0 đã được chủ dự án cài, xem danh sách ảnh màn hình và tạo bản nén. Luồng giao hàng 0.2.0 cần kiểm thử mới. CI kiểm thử logic/điều hướng không xác nhận Zalo, file provider và các tình huống dưới đây trên máy thật.

## Sổ giao hàng

1. Nhập phiếu thử từ Ảnh/Tệp/camera, lưu nháp rồi đóng mở app. Ảnh phải xem được sau khi nguồn trong Photos bị xóa; chỉ thử bằng ảnh kiểm thử.
2. Xác nhận ngày ký cuối tháng: công nằm đúng tháng đó; đổi mức công sau đó không sửa phiếu đã ký. Giao thất bại hoặc CK sau vẫn giữ công.
3. Chọn thư mục Bill 3.2.0, xem trước phiếu mới và phiếu cũ có tiền thu. Nhập cùng gói ba lần: một hồ sơ/một công; cùng khách hai mã khác nhau không bị gộp. Kiểm tra ảnh cũ nằm ngoài thư mục được cấp quyền có cảnh báo, không tự mất khoản thu.
4. Thử các nhánh tiền: 2.165.000 = 1.500.000 CK + 665.000 tiền mặt. Đổi tiền mặt thành 600.000 phải còn 65.000; 700.000 phải bị chặn vì thừa. CK sau giữ hai khoản 0. Đổi kết quả giao không tự xóa khoản đã nhận.
5. CK có ảnh giao dịch vẫn chờ công ty xác nhận. Xác nhận đối soát có ghi chú; sửa lần chốt làm CK cần đối soát lại.
6. Báo cáo thiếu phiếu khách ký / giao dịch khi bắt buộc phải báo thiếu. Xem thứ tự ảnh, sửa nội dung, chia sẻ sang đúng Zalo trên iPhone 11/iOS 18.7.8. Thử nhiều ảnh + nội dung, và phương án sao chép riêng caption.
7. Hủy bảng chia sẻ: khoản thu còn nguyên, chưa đánh dấu đã gửi. Chỉ nút xác nhận riêng mới ghi đã báo cáo. Sửa tiền hoặc bổ sung ảnh làm báo cáo cần gửi lại, không cộng công/tiền thêm.
8. Nộp tiền công ty: tiền còn giữ = tiền mặt thu − nộp, không trừ công. Nhập nhầm lần nộp rồi điều chỉnh: có lý do/lịch sử và số tiền quay về đúng. Hủy hồ sơ nhập nhầm giữ lịch sử công.
9. Đối soát một tháng có nhiều phiếu và xuất CSV, kiểm đủ danh sách; đối chiếu chênh số với kế toán. CSV không tính theo bộ lọc danh sách Đơn hàng.
10. Xuất sao lưu ra Tệp; chọn lại để kiểm tra và khôi phục dữ liệu thử. Kiểm cả ảnh, công, khoản thu, báo cáo và lần nộp. Bản hỏng/thiếu ảnh không được thay sổ đang dùng. Thử xuất bản giữ trước khôi phục.
11. Thử Dynamic Type, Light/Dark Mode, màn ngang; số tiền dài và tên khách dài không che nút thao tác. Không gỡ app chứa sổ thật để thử cài.

## Công cụ ảnh giữ từ 0.1.0

1. Cài IPA bằng tài khoản/công cụ sideload của Sếp. Kiểm tra tên, icon, Light/Dark Mode, chữ lớn và xoay màn hình.
2. Mở app: chưa yêu cầu ảnh ngay. Mở Ảnh trùng rồi cấp quyền giới hạn một vài ảnh thử. Phạm vi phải phản ánh đúng phần được cấp quyền. Thử từ chối quyền và mở lại qua Cài đặt.
3. Chuẩn bị hai bản ảnh JPEG giống hệt, một ảnh khác, Live Photo và ảnh đã chỉnh sửa. Quét: chỉ ảnh đủ điều kiện cùng dữ liệu mới vào nhóm. Không coi ảnh gần giống là trùng.
4. Thử chọn toàn bộ một nhóm để xóa: app phải ngăn và giữ ít nhất một bản. Hủy xác nhận không được xóa ảnh. Chỉ thử xóa trên ảnh kiểm thử; kiểm tra Đã xóa gần đây và đồng bộ iCloud.
5. Tắt tải iCloud, thử ảnh gốc chưa ở máy: phải báo không đọc được/bỏ qua, không kết luận đã quét đầy đủ. Bật tải khi muốn thử lại bằng Wi-Fi.
6. Đổi giới hạn ảnh trong Cài đặt, đóng/mở app: giá trị phải giữ lại. Trong lúc quét đổi ảnh ở ứng dụng Photos, quay lại: kết quả cũ phải bị hủy/tải lại.
7. Nén ảnh chữ/hóa đơn JPEG, PNG trong suốt, HEIC và ảnh có chiều xoay EXIF. So sánh chữ/màu, kích thước, hướng ảnh; kết quả JPEG không giữ GPS/EXIF. Lưu/chia sẻ xong ảnh gốc vẫn còn. Nếu bản mới lớn hơn phải báo đúng.
8. Trong Files chọn thư mục chứa file lớn, thư mục con và file iCloud chưa tải. Kiểm tra kích thước/sắp xếp và Quick Look; không truy cập ngoài thư mục, không tự xóa tài liệu.
9. Chuyển app/khóa máy trong lúc quét hoặc nén rồi quay lại. Ghi nhận trường hợp gián đoạn, treo hoặc thông báo sai. Không coi chạy nền dài là tính năng đã xác nhận.

Khi báo lỗi: ghi bước thao tác, quyền ảnh, trạng thái iCloud, loại ảnh và màn hình báo lỗi. Không đưa pairing, tài khoản Apple hoặc ảnh có dữ liệu khách hàng lên issue công khai.
