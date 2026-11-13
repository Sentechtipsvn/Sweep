# Sweep 0.3.1 — sửa hộp thư chia sẻ khi ký bằng AltStore

Video thử trên iPhone cho thấy SweepShare mở được từ Zalo nhưng không truy cập được container chung. Giữ extension không đồng nghĩa với việc App Groups đã được cấp đúng cho cả hai tiến trình.

## Nguyên nhân trong 0.3.0

1. Gói build tắt code signing không có LC_CODE_SIGNATURE, nên không chứa khai báo entitlement App Groups trong executable của cả app lẫn extension. AltStore đọc entitlements của IPA để quyết định bật capability và tạo provisioning profile. Tệp `.entitlements` trong repo không tự nằm trong IPA.
2. App đọc duy nhất `SweepAppGroupIdentifier` cố định. AltStore đổi nhóm theo tài khoản ký và ghi nhóm thực vào `ALTAppGroups` của từng bundle. Tên cấu hình riêng của Sweep không được AltStore tự đổi.

Đối chiếu mã nguồn AltStore tại commit `56854e66fef2eac32dad88dcbad1dc131d430e60`: `FetchProvisioningProfilesOperation.swift` đọc `app.entitlements[.appGroups]`; `ResignAppOperation.swift` ghi groups từ profile vào Info.plist; `Shared/Extensions/Bundle+AltStore.swift` xác định khóa `ALTAppGroups`.

## Bản sửa

- Đóng gói với chữ ký ad-hoc để giữ metadata App Groups thật trong executable của cả app và extension. Đây không phải chữ ký Apple cho phép cài trên iPhone; Sếp vẫn dùng AltStore ký và cài.
- Bước đóng gói đọc lại Mach-O của hai executable, kiểm tra chính xác quyền nhóm, xác minh chữ ký/resource bundle và checksum. Không chỉ kiểm tra khóa trong Info.plist.
- Lúc chạy ưu tiên nhóm do AltStore cấp qua `ALTAppGroups`; chỉ dùng nhóm cấu hình gốc khi không có thông tin remap. Không tự suy đoán Team ID hay tên nhóm mới.
- Thông báo lỗi phân biệt extension đã mở với quyền container chưa cấp, kèm nguồn/tên nhóm để chẩn đoán.
- Giữ vị trí SQLite, ảnh chứng từ và dữ liệu cũ; không đổi bundle ID gốc. Sửa một selector của bài test Bill sau khi nút nhận ảnh chuyển thành menu.

## Kiểm chứng

Bổ sung bốn kiểm thử chọn nhóm: AltStore remap, ký thông thường, nhóm rỗng/sai và tính nhất quán giữa app/extension. CI kiểm tra core, build iPhone và kiểm tra entitlement trong IPA; bài kiểm tra giao diện chạy riêng. Chỉ xác nhận kết quả sau khi CI trả về. Luồng App Groups thật của AltStore vẫn cần thử trên iPhone sau khi ký lại bản 0.3.1.

Không cần gỡ app đang chứa dữ liệu. Xuất sao lưu trước khi cài đè, giữ extension khi AltStore hỏi. Không ký lại bản 0.3.0 để thử sửa lỗi này.
