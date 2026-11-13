"""Bill shares immutable intake metadata with the order manager.

The original automatic OCR rules are preserved. No delivery/payment ledger is
opened or rewritten here, so recording a new invoice cannot reset old receipts.
"""
from __future__ import annotations

import copy
import json
import plistlib
from pathlib import Path

from shortcut_builder import Builder, BUILD, VERSION, MONTH_PATTERN, ref, token, storage, current_time, uid, output


SAVE = "💾 Lưu đơn"
EDIT_NAME = "✏️ Sửa tên khách"
EDIT_TOTAL = "✏️ Sửa số tiền"
EDIT_CODE = "🧾 Sửa mã phiếu"
EDIT_ADDRESS = "📍 Sửa địa chỉ"
EDIT_PHONE = "☎️ Sửa điện thoại"
EDIT_NOTE = "🕒 Sửa ghi chú giao hàng"
CODE_PATTERN = r'\A[A-Za-z0-9][A-Za-z0-9./_-]{0,47}\z'
HEADER_PATTERNS = {
    "BillCode": r'(?im)(?:^|[ \t])[Ss][ốoô]\p{M}*\s*[:：]\s*([^\s]+)',
    "BillAddress": r'(?im)(?:^|[ \t])[ĐđDd][ịi]\p{M}*a[ \t]+ch[ỉi]\p{M}*[ \t]*[:：][ \t]*([^\r\n]+)',
    "BillPhone": r'(?im)(?:^|[ \t])[ĐđDd]i[ệeê]\p{M}*n[ \t]+tho[ạa]\p{M}*i[ \t]*[:：][ \t]*([+0-9][0-9 .()+-]{8,22})',
    "BillDeliveryNote": r'(?im)(?:^|[ \t])[ĐđDd][ịi]\p{M}*a[ \t]+ch[ỉi]\p{M}*[ \t]+giao[ \t]+h[àa]\p{M}*ng[ \t]*[:：][ \t]*([^\r\n]+)'
}

def header_fields(b):
    # Proven OCR action UUID from the supplied Bill 3.2.0 (248-action graph).
    raw = output("2DB7BBEA-3304-4EBA-90CA-00EC058ECB2E", "Văn bản sạch")
    for key, pattern in HEADER_PATTERNS.items():
        b.set(key, "")
        matches = b.match(raw, pattern)
        with b.if_(b.count(matches), "gt", 0):
            selected = b.first(matches)
            value = b.replace(selected, r'^[^:：]*[:：][ \t]*', "")
            # Stop at adjacent labels when OCR flattens the two header columns.
            value = b.replace(value, r'(?i)[ \t]+(?:NV[ \t]+b[áa]\p{M}*n[ \t]+h[àa]\p{M}*ng|[ĐđDd]i[ệeê]\p{M}*n[ \t]+tho[ạa]\p{M}*i|[ĐđDd][ịi]\p{M}*a[ \t]+ch[ỉi]\p{M}*)[ \t]*[:：].*$', "")
            value = b.replace(value, r'^\s+|\s+$', "")
            if key == "BillCode":
                value = b.first(b.split(value, " "))
                with b.if_(b.match(value, CODE_PATTERN)):
                    b.set(key, value)
            elif key == "BillPhone":
                value = b.replace(value, r'[^+0-9]', "")
                with b.if_(b.match(value, r'\A(?:0[0-9]{9,10}|\+84[0-9]{9,10})\z')):
                    b.set(key, value)
            else:
                b.set(key, value)

def read_code(b):
    entered = b.ask("Mã phiếu cạnh Số: trên ảnh (bắt buộc)", ref("BillCode"))
    entered = b.replace(entered, r'^\s+|\s+$', "")
    with b.if_(b.match(entered, CODE_PATTERN)):
        b.set("BillCode", entered)
        b.otherwise()
        b.alert("Mã phiếu chưa hợp lệ", "Nhập mã đúng trên phiếu; chỉ chữ, số, / . _ hoặc -. Chưa lưu đơn.")



def read_name(b, default=""):
    entered = b.ask("Tên khách của đơn hàng", default, var="EnteredName")
    entered = b.replace(entered, r'\s+', " ")
    b.replace(entered, r'^\s+|\s+$', "", "EnteredName")
    with b.if_(b.match(ref("EnteredName"), r'\p{L}')):
        b.set("BillName", ref("EnteredName"))
        b.otherwise()
        b.alert("Tên khách chưa hợp lệ", "Tên cần có chữ cái. Chưa có tệp nào được lưu.")


def read_total(b, default=""):
    entered = b.ask("Tổng tiền đơn bằng đồng, không nhập dấu chấm (ví dụ 2136000)", default, "Number")
    with b.if_(b.match(entered, r'\A[0-9]+\z')):
        b.replace(entered, r'^0+(?=[0-9])', "", "BillTotal")
        b.otherwise()
        b.alert("Số tiền chưa hợp lệ", "Nhập số nguyên không âm, không có dấu phân cách. Chưa có tệp nào được lưu.")


def build_bill():
    b = Builder()
    # Keep the original proven automatic extraction, excluding its old save path
    # and its permissive manual-money cleanup. All downstream state is new.
    b.actions = copy.deepcopy(json.loads(Path(__file__).with_name('bill_ocr_actions.json').read_text()))
    for i, a in enumerate(b.actions):
        a['WFWorkflowActionParameters'].setdefault('UUID', uid(f'bill-ocr:{i}'))
    b.actions[0]['WFWorkflowActionParameters']['WFCommentActionText'] = (
        f"Bill {VERSION} · © Sentechtipsvn\nChia sẻ ảnh đơn vào Bill, kiểm tra tên tiệm, mã Số:, địa chỉ, điện thoại và tiền rồi lưu. "
        "Ảnh và thông tin đơn được lưu chung với Ảnh đơn hàng 3.2.0, không chọn thư mục riêng. "
        "Bill chỉ tạo đơn mới, không thay đổi trạng thái đã giao hoặc tiền đã thu."
    )
    header_fields(b)
    b.set("BillName", "")
    b.set("BillTotal", "")
    with b.if_(ref("Đã có tên khách"), "eq", "1"):
        b.set("BillName", ref("Tên khách đã chọn"))
    with b.if_(ref("Đã có tiền tổng"), "eq", "1"):
        b.set("BillTotal", ref("Tiền tổng đã chọn"))
    # Three attempts keep manual fallback bounded; Cancel always stops natively.
    with b.repeat(3):
        with b.if_(ref("BillName"), "empty"):
            read_name(b)
        with b.if_(ref("BillTotal"), "empty"):
            read_total(b)
        with b.if_(ref("BillCode"), "empty"):
            read_code(b)
    with b.if_(ref("BillName"), "empty"):
        b.alert("Chưa đủ dữ liệu", "Chưa có tên khách hợp lệ, chưa lưu ảnh hoặc đơn.")
        b.stop()
    with b.if_(ref("BillTotal"), "empty"):
        b.alert("Chưa đủ dữ liệu", "Chưa có tổng tiền hợp lệ, chưa lưu ảnh hoặc đơn.")
        b.stop()

    with b.if_(ref("BillCode"), "empty"):
        b.alert("Thiếu mã phiếu", "Chưa lưu đơn. Mã cạnh Số: giúp Sweep nhận đúng hồ sơ.")
        b.stop()

    with b.repeat(20):
        with b.menu(token("Bill — ", ref("BillName"), "\n", b.money(ref("BillTotal")), "₫\nSố: ", ref("BillCode"), "\nĐịa chỉ: ", ref("BillAddress"), "\nĐiện thoại trên phiếu: ", ref("BillPhone"), "\nGhi chú giao: ", ref("BillDeliveryNote"), "\nSĐT có thể thuộc NV bán hàng; xác minh trước khi gọi."),
                    [SAVE, EDIT_NAME, EDIT_TOTAL, EDIT_CODE, EDIT_ADDRESS, EDIT_PHONE, EDIT_NOTE, "👁️ Xem ảnh", "Huỷ"]):
            b.case(SAVE)
            current_time(b)
            with b.if_(b.match(ref("CurrentMonth"), MONTH_PATTERN), "empty"):
                b.alert("Chưa đọc được ngày lưu", "Chưa tạo đơn để tránh lưu sai tháng. Sếp kiểm tra ngày giờ máy rồi thử lại.")
                b.stop()
            storage(b)
            safe_name = b.replace(ref("BillName"), r'[/:\\\x00-\x1f\x7f]', "–")
            safe_name = b.first(b.match(safe_name, r'\A.{1,40}'))
            safe_name = b.text(safe_name)
            b.set("UniqueNameReady", "0")
            # Collision check makes even same-second double-runs non-overwriting.
            with b.repeat(5):
                with b.if_(ref("UniqueNameReady"), "eq", "0"):
                    nonce = b.add("number.random", WFRandomNumberMinimum=100000, WFRandomNumberMaximum=999999)
                    b.text(token(ref("ReportStamp"), "-", nonce), "ImageKey")
                    b.text(token(safe_name, " - ", b.money(ref("BillTotal")), " · ", ref("ImageKey"), ".png"), "BillFilename")
                    existing = b.load(ref("ImagesFolder"), ref("BillFilename"))
                    with b.if_(b.count(existing), "le", 0):
                        b.set("UniqueNameReady", "1")
            with b.if_(ref("UniqueNameReady"), "eq", "0"):
                b.alert("Chưa tạo được tên tệp riêng", "Không ghi đè ảnh cũ. Sếp chạy lại Bill.")
                b.stop()
            b.hash(b.text(token("sen-bill-v1:", ref("ImageKey"))), "BillID")
            # Save the image first. An interrupted metadata write remains recoverable
            # from the self-describing filename when the manager next scans.
            image = b.add("image.convert", WFInput=ref("Hình ảnh"), WFImageFormat="PNG", WFImagePreserveMetadata=False)
            b.save(image, ref("ImagesFolder"), ref("BillFilename"), "SavedBillImage", overwrite=False)
            reloaded_image = b.load(ref("ImagesFolder"), ref("BillFilename"))
            image_check = b.add("filter.images", WFContentItemInputParameter=reloaded_image, WFContentItemLimitEnabled=False)
            with b.if_(b.count(image_check), "le", 0):
                b.alert("Chưa xác minh được ảnh đã lưu", "Chưa báo hoàn tất. Sếp kiểm tra iCloud và thư mục ảnh trước khi lưu lại để tránh trùng đơn.")
                b.stop()
            b.dictionary({"schema": "sen-bill-v1", "version": VERSION, "id": ref("BillID"),
                          "filename": ref("BillFilename"), "imageKey": ref("ImageKey"), "name": ref("BillName"), "total": ref("BillTotal"),
                          "createdAt": ref("NowISO"), "createdMonth": ref("CurrentMonth"),
                          "invoiceCode": ref("BillCode"), "address": ref("BillAddress"), "phone": ref("BillPhone"),
                          "phoneSource": "invoice-unverified", "deliveryNote": ref("BillDeliveryNote")}, "BillRecord")
            b.text(ref("BillRecord"), "BillJSON")
            b.save(ref("BillJSON"), ref("IncomingFolder"), token(ref("BillID"), ".json"), overwrite=False)
            stored = b.load(ref("IncomingFolder"), token(ref("BillID"), ".json"))
            with b.if_(b.hash(b.text(stored)), "ne", b.hash(ref("BillJSON"))):
                b.alert("Ảnh đã lưu, thông tin chưa xác minh", "Ảnh đơn đã được giữ. Sếp mở Ảnh đơn hàng để kiểm tra; chưa cần lưu lại cùng ảnh.")
                b.stop()
            b.alert("Đã lưu đơn", token(ref("BillName"), " — ", b.money(ref("BillTotal")), "₫\nTrong Sweep 0.2.1: Nhập Bill → chọn SenTechTips_AnhDonHang → mở hồ sơ → Nhập đơn vào Sweep. Ảnh đơn hàng 3.2.0 vẫn đọc được. Ảnh nằm trong iCloud Drive/Shortcuts/SenTechTips_AnhDonHang/Ảnh Đơn Hàng."))
            b.stop()
            b.case(EDIT_NAME)
            read_name(b, ref("BillName"))
            b.case(EDIT_TOTAL)
            read_total(b, ref("BillTotal"))
            b.case(EDIT_CODE)
            read_code(b)
            for branch, key, prompt in [(EDIT_ADDRESS, "BillAddress", "Địa chỉ trên phiếu"), (EDIT_PHONE, "BillPhone", "Điện thoại in trên phiếu (có thể là NV bán hàng)"), (EDIT_NOTE, "BillDeliveryNote", "Ghi chú / giờ hẹn giao hàng")]:
                b.case(branch)
                b.ask(prompt, ref(key), var=key)
            b.case("👁️ Xem ảnh")
            b.add("previewdocument", WFInput=ref("Hình ảnh"))
            b.case("Huỷ")
            b.stop()

    workflow = {"WFWorkflowActions": b.actions,
                "WFWorkflowClientVersion": "3612.0.1.3", "WFWorkflowMinimumClientVersion": 1106,
                "WFWorkflowMinimumClientVersionString": "1106", "WFWorkflowIcon": {"WFWorkflowIconStartColor": 431817727, "WFWorkflowIconGlyphNumber": 59511},
                "WFWorkflowName": "Bill", "WFWorkflowInputContentItemClasses": ["WFImageContentItem"],
                "WFWorkflowOutputContentItemClasses": [], "WFWorkflowTypes": ["ActionExtension"], "WFQuickActionSurfaces": [],
                "WFWorkflowHasShortcutInputVariables": True, "WFWorkflowHasOutputFallback": False,
                "WFWorkflowImportQuestions": []}
    from ui_catalog import centralize
    workflow = centralize(workflow)
    BUILD.mkdir(exist_ok=True)
    (BUILD / f"Bill-v{VERSION}-unsigned.shortcut").write_bytes(plistlib.dumps(workflow, fmt=plistlib.FMT_BINARY, sort_keys=False))
    (BUILD / "bill-workflow.json").write_text(json.dumps(workflow, ensure_ascii=False, indent=2))
    return workflow


if __name__ == '__main__':
    print(f"Built Bill: {len(build_bill()['WFWorkflowActions'])} native actions")
