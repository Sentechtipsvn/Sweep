# Sendeli 0.8.1 · build 15

- Tìm kiếm: chỉ một gợi ý hiện tại; chữ cũ trượt sang phải và mờ hết trước khi chữ mới đi vào, chu kỳ 2 giây. Dừng khi nhập, khi app không hoạt động và khi bật Giảm chuyển động.
- Hai nút Đang giao / Đã giao nằm ngay dưới tìm kiếm. Nhắc việc nằm bên phải dòng thời gian trong Đã giao, cùng cỡ chữ và ẩn khi không còn việc. Đơn chành đang theo dõi cũng được tính.
- Nhắc chuyển khoản và giao chành mở màn hình riêng với Khách chuyển khoản rồi / Huỷ. Xác nhận đủ phần còn thiếu sẽ ghi một sự kiện chuyển khoản gắn với lần chốt giao hiện tại; không đổi nhánh giao, công ký nhận hay trạng thái chứng từ đã gửi. Việc thiếu chứng từ vẫn được giữ riêng.
- Xác nhận khách chuyển khoản cập nhật CK khách báo và phần còn lại; đối soát kế toán vẫn là thao tác riêng. Sổ lưu theo lịch sử chỉ thêm, hỗ trợ sổ cũ chưa có trường xác nhận.
- Lịch sử: giữ nút Tất cả màu xanh để xem/tìm đơn; bỏ danh sách phiếu tính công lặp lại cuối trang. Vẫn giữ số tổng và xuất CSV.
- Cài đặt: bỏ lối vào Liên hệ, Dọn dẹp, Chấm công đã có trong Công cụ.

Kiểm chứng bằng workflow reminder-layout-validation.yml: toàn bộ kiểm thử Swift, dựng Release cho iPhone kèm Share Extension, và kiểm thử giao diện iPhone 11 iOS 18.5. IPA cần AltStore ký để cài. Chưa kiểm chứng trên iPhone vật lý của Sếp.
