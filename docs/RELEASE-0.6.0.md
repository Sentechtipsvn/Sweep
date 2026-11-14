# Sweep 0.6.0 (10) — cập nhật 02

Nút gọi tròn xanh sát phải, nút Maps gọn, chọn/chụp ảnh xếp dọc. Thêm chọn từ Danh bạ, xác nhận số trùng và đọc QR Zalo tùy chọn; giữ liên hệ, vị trí và chức năng cũ.

Thêm lịch chấm công và bảng lương theo công thực làm. Nghỉ không lương trừ quỹ 12 ngày/năm; đúng 3 ngày nghỉ vẫn có chuyên cần, hơn 3 ngày mất. Giá xăng chốt ngày 30 (tháng 2: ngày cuối tháng) dùng cả tháng. Bảng lương chốt vào ngày cuối tháng, kể cả 28/29/30/31; giữ bản tính khi mở khóa, có CSV, khoản ứng và điều chỉnh có lý do.

Trước khi tính lương thật, cấu hình lịch làm việc, loại/vùng xăng và mức tiền của tháng. Giá xăng nhập tay có nguồn/ngày; chưa bật dịch vụ tự động lấy giá. Số 4,5 ngày nghỉ trong ảnh cũ không tự nhập vào năm hiện tại.

Nhắc gia hạn dựa trên ngày đọc được từ profile bản ký đang cài, hoặc ngày người dùng nhập nếu không đọc được. Bắt đầu 24 giờ trước hạn, mỗi 3 giờ, lô 48 thông báo. Sau khi refresh cần mở Sweep để nhận hạn mới và hủy lịch cũ; không có cam kết iOS chuyển thông báo khi chữ ký đã hết hạn.

Thêm tác vụ App Intents “Nhận phiếu Sweep” để cấu hình Phím tắt nhận ảnh từ bảng chia sẻ và mở app. Giữ Share Extension cũ. Luồng Zalo/Phím tắt và profile ký lại cần thử trên iPhone; simulator/build không thay thế kiểm tra này. Không dùng API riêng tư để tự bật app từ Share Extension.

Sổ nâng từ schema 1/2 lên 3 có bản sao trước nâng cấp; sao lưu/khôi phục gồm dữ liệu công và lương. Không tự xóa dữ liệu và không cập nhật nguồn AltStore. Bàn giao IPA trực tiếp sau khi build và kiểm thử.
