import json
import unicodedata
import unittest
from bill_builder import build_bill, SAVE, EDIT_CODE
from simulate_shortcut import Simulator, File, validate

# Synthetic invoice only; no customer data is published.
OCR = '''Ngày 12 tháng 11 năm 2026
Số : 7856
Người mua hàng :    NV bán hàng : NHÂN VIÊN THỬ
Đơn vị : BÁNH THỬ NGHIỆM    Điện thoại : 0900000000
Địa chỉ : 12 Đường Mẫu, TP HCM
Địa chỉ giao hàng : Trước 10h sáng
Tên hàng hóa Số lượng Thành tiền
Mặt hàng mẫu 1 2.200.000
Chiết khấu -64.000
Tổng thanh toán: 2.136.000
'''

class BillTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.workflow = build_bill()
    def run_bill(self, ocr=OCR, choices=None, answers=None, files=None):
        return Simulator(self.workflow, shortcut_input=[File('share/invoice.png', ocr, width=1200, height=800, image_format='PNG')], choices=choices or [SAVE], answers=answers, files=files).run()
    def record(self, sim):
        return next(json.loads(f.data) for p,f in sim.files.items() if '/Đơn mới/' in p)
    def test_graph(self): validate(self.workflow)
    def test_complete_header_and_grand_total(self):
        r=self.record(self.run_bill())
        self.assertEqual(r['invoiceCode'],'7856')
        self.assertEqual(r['address'],'12 Đường Mẫu, TP HCM')
        self.assertEqual(r['phone'],'0900000000')
        self.assertEqual(r['deliveryNote'],'Trước 10h sáng')
        self.assertEqual(r['name'],'BÁNH THỬ NGHIỆM')
        self.assertEqual(r['total'],'2136000')
        self.assertEqual(r['schema'],'sen-bill-v1')
    def test_missing_code_requires_input(self):
        r=self.record(self.run_bill(ocr=OCR.replace('Số : 7856',''), answers=['7857']))
        self.assertEqual(r['invoiceCode'],'7857')
    def test_cancel_never_writes(self): self.assertEqual(self.run_bill(choices=['Huỷ']).files,{})
    def test_edit_code(self):
        r=self.record(self.run_bill(choices=[EDIT_CODE,SAVE],answers=['FIX-2']))
        self.assertEqual(r['invoiceCode'],'FIX-2')
    def test_old_ledger_untouched(self):
        path='Shortcuts/SenTechTips_AnhDonHang/orders.json'
        files={path:File(path,'old cash and bank ledger')}
        s=self.run_bill(files=files)
        self.assertEqual(s.files[path].data,'old cash and bank ledger')
    def test_same_second_never_overwrites(self):
        first=self.run_bill();second=self.run_bill(files=first.files)
        self.assertEqual(len([p for p in second.files if '/Đơn mới/' in p]),2)
    def test_manual_fallback(self):
        r=self.record(self.run_bill(ocr='Ảnh mờ', answers=['TIỆM THỬ','100000','M-01']))
        self.assertEqual((r['name'],r['total'],r['invoiceCode']),('TIỆM THỬ','100000','M-01'))

if __name__=='__main__': unittest.main()
