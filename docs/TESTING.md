# Sweep 0.1.0 — thử trên iPhone

Trạng thái ban đầu: chưa chạy trên iPhone thật. CI kiểm thử logic và biên dịch không xác nhận các tình huống dưới đây.

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
