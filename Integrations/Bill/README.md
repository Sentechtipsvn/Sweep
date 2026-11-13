# Bill 3.3.0 ↔ Sweep 0.2.1

Bill 3.2.0 do người dùng gửi đã được giải mã và đối chiếu: toàn bộ 248 actions trùng với builder nguồn cũ. Bản 3.3.0 giữ OCR tên/tổng tiền và cách lưu, thêm mã cạnh “Số:”, địa chỉ, điện thoại trên phiếu và ghi chú giao hàng. Mã phiếu bắt buộc kiểm tra trước khi lưu.

`sen-bill-v1` giữ nguyên `id`, công thức SHA256, `imageKey`, tên ảnh và các khóa cũ. Các khóa mới tùy chọn: `invoiceCode`, `address`, `phone`, `phoneSource`, `deliveryNote`. Không ghi đè `orders.json`, tiền mặt, CK hoặc lịch sử bên Ảnh đơn hàng. Không tự tính công đơn. Ảnh đơn hàng 3.2.0 vẫn đọc được name/total.

Sweep chọn thư mục cha `SenTechTips_AnhDonHang`, mở một hồ sơ rồi xác nhận **Nhập đơn vào Sweep**. Danh sách tìm thấy là xem trước, chưa ghi sổ. Sweep giữ sổ cũ và tiền cũ ưu tiên, chỉ bổ sung các trường đầu phiếu còn thiếu từ sidecar mới. Ảnh cũ chưa có thông tin này được đọc bằng Vision ngay trên máy; kết quả phải được đối chiếu trước khi lưu. OCR không tự sửa tên/tiền đã có của Bill. Thông tin không đọc rõ vẫn nhập tay được và lỗi hiện tại chỗ.

Điện thoại cạnh NV bán hàng có thể thuộc nhân viên bán hàng; không mặc định là số khách nhận. “Địa chỉ giao hàng” dạng “Trước 10h sáng” là ghi chú, không được thay thế địa chỉ bản đồ.

## Build / kiểm tra

- Python 3 + `regex`: `python -m unittest discover -s Integrations/Bill -p test_bill.py -v`
- Tạo plist: `python Integrations/Bill/bill_builder.py`
- Ký trên macOS: `shortcuts sign --mode anyone --input Integrations/Bill/build/Bill-v3.3.0-unsigned.shortcut --output Integrations/Bill/build/Bill-v3.3.0.shortcut`
- CI ghi kết quả ký thực tế vào SIGNING-STATUS.json; không coi plist chưa ký là bản cài được.
- `swift test` kiểm tra tiền, lịch sử, parser, schema cũ/mới và OCR Vision trên phiếu tổng hợp. Không đưa hóa đơn riêng của khách vào repo công khai.
- Native UI test kiểm tra xem trước → OCR → nhập → mở chi tiết → khởi động lại vẫn còn đơn → nhập lại mở hồ sơ cũ.

Bản beta cần kiểm tra thêm quyền Tệp/iCloud và OCR ảnh thật trên iPhone. Cài đè cùng bundle ID `com.sentechtipsvn.sweep` để giữ dữ liệu; xuất sao lưu trước khi cập nhật.
