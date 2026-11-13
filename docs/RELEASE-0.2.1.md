# Sweep 0.2.1 (3) — bản thử nghiệm

- Sửa luồng nhập Bill: tách xem trước và lưu vào sổ, nút nhập luôn thấy, báo rõ dữ liệu bắt buộc còn thiếu, mở hồ sơ sau khi lưu xong và đóng sheet.
- Đọc thông tin hóa đơn bằng Vision trên thiết bị cho ảnh Bill cũ hoặc ảnh chọn từ Tệp/Ảnh: tên tại Đơn vị:, mã cạnh Số:, địa chỉ, điện thoại, Tiền hàng/tổng thanh toán và ghi chú giao.
- Nhận trường mở rộng Bill 3.3.0; vẫn đọc 3.2.0 và sổ sen-orders-v3. Giữ nguyên tiền mặt, CK, ngày lưu, trạng thái và snapshot nguồn cũ.
- OCR chỉ điền phần trống, không tự ghi đè tiền/tên có sẵn của Bill. Kết quả cần kiểm tra; không tự nhập, xóa nguồn, ký nhận hay cộng công.
- Bỏ NavigationStack lồng khi mở hồ sơ Bill; chờ sheet đóng trước khi chuyển sang hồ sơ đã lưu. Đặt lại bộ lọc để đơn vừa nhập nhìn thấy được.
- Hiển thị phiên bản theo Info.plist để tránh nhầm bản cài.

Bill 3.3.0 giữ nguyên schema/ID/cách lưu ảnh, thêm trường đầu phiếu và menu sửa, bắt buộc mã phiếu trước khi lưu. SĐT trên phiếu có thể thuộc NV bán hàng; ghi rõ cần xác minh.

Cài đè đúng bundle ID com.sentechtipsvn.sweep, không gỡ app có dữ liệu. IPA chưa ký, cần AltStore hoặc công cụ ký phù hợp. Không cần VPN. Quyền iCloud và OCR ảnh thật cần kiểm tra tiếp trên iPhone.
