import SwiftUI

private struct AttendanceDay: Identifiable { let date: Date; var id: Date { date } }

struct PayrollView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var month = DeliveryMonth.start(Date())
    @State private var day: AttendanceDay?
    @State private var configure = false
    @State private var advance = false
    @State private var confirmClose = false
    @State private var reopen = false
    @State private var reason = ""
    @State private var sharing: DeliveryShare?
    private var book: PayrollBook { store.ledger.payroll ?? PayrollBook() }
    private var period: PayrollMonth { book.period(month) }
    private var closed: PayrollSnapshot? { book.closed(month) }
    private var result: PayrollCalculation { closed?.calculation ?? PayrollCalculation(ledger: store.ledger, period: period) }
    private var year: Int { PayrollDates.calendar.component(.year, from: month) }
    var body: some View {
        List {
            Section {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.buttonStyle(.borderless)
                    Spacer()
                    Text("Tháng \(PayrollDates.calendar.component(.month, from: month)) / \(year)").font(.headline)
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.buttonStyle(.borderless)
                }
                Label(closed == nil ? "Lương tạm tính" : "Bảng lương đã chốt", systemImage: closed == nil ? "clock" : "lock.fill")
                    .font(.caption).foregroundStyle(closed == nil ? Color.secondary : Color.green)
                Text(VND.format(result.net)).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                    .accessibilityIdentifier("payroll.net")
                HStack {
                    summary("Công", units: result.workUnits)
                    Spacer()
                    summary("Nghỉ", units: result.leaveUnits)
                    Spacer()
                    VStack { Text("\(result.commissions)").font(.headline); Text("Đơn").font(.caption).foregroundStyle(.secondary) }
                }
                if !period.policy.confirmed { Label("Chọn lịch làm việc và xác nhận mức lương trước khi chốt.", systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange) }
                if result.missingDays > 0 { Text("\(result.missingDays) ngày làm việc chưa chấm; ngày trống không tự coi là nghỉ.").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Chấm công") { calendar }
            Section("Phép năm \(year)") {
                LabeledContent("Đã nghỉ / hạn mức", value: "\(units(book.annualLeaveUnits(year: year))) / 12 ngày")
                let remaining = 24 - book.annualLeaveUnits(year: year)
                Text(remaining < 0 ? "Vượt \(units(-remaining)) ngày. Vẫn giữ toàn bộ ngày nghỉ để đối chiếu." : "Còn \(units(remaining)) ngày phép không lương.")
                    .font(.footnote).foregroundStyle(remaining < 0 ? Color.red : Color.secondary)
                Text("Nghỉ quá 3 ngày/tháng mất chuyên cần. Đúng 3 ngày vẫn giữ.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Các khoản tháng này") {
                ForEach(result.rows, id: \.0) { label, value in
                    LabeledContent(label, value: label == "Xăng xe" && !result.fuelConfirmed ? "Chờ chốt giá" : VND.format(value))
                }
                LabeledContent("Công chuẩn", value: units(result.plannedUnits) + " ngày")
                LabeledContent("Chốt lương", value: PayrollDates.closeDay(month).formatted(date: .numeric, time: .omitted))
                LabeledContent("Ngày chốt giá xăng", value: PayrollDates.fuelDay(month).formatted(date: .numeric, time: .omitted))
                if let fuel = period.fuel {
                    Text("\(fuel.price)₫/lít · \(fuel.source)").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Giá ngày 30 áp dụng cho cả tháng; tháng 2 dùng ngày cuối tháng. Không có giá đúng thì để chờ chốt.").font(.footnote).foregroundStyle(.orange)
                }
            }
            Section("Tạm ứng") {
                ForEach(period.advances) { item in
                    VStack(alignment: .leading) {
                        LabeledContent(item.day.formatted(date: .numeric, time: .omitted), value: VND.format(item.amount))
                        if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if closed == nil { Button("Thêm khoản tạm ứng", systemImage: "plus.circle") { advance = true } }
            }
            Section {
                if closed == nil {
                    Button("Cấu hình lương và giá xăng", systemImage: "slider.horizontal.3") { configure = true }.accessibilityIdentifier("payroll.configure")
                    Button("Chốt bảng lương tháng", systemImage: "lock") { confirmClose = true }.disabled(store.busy || store.blocked)
                        .accessibilityIdentifier("payroll.close")
                } else {
                    Button("Mở khóa để điều chỉnh", systemImage: "lock.open") { reason = ""; reopen = true }
                }
                Button("Xuất bảng lương CSV", systemImage: "square.and.arrow.up") { exportCSV() }
            }
            Section {
                Text("Chấm công thủ công; đơn đã ký chỉ gợi ý ngày đi làm. Tiền thu hộ không cộng vào lương. Mức tiền và lịch làm việc áp dụng theo cấu hình tháng.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Chấm công & lương").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $day) { item in
                NavigationStack { AttendanceEditor(day: item.date, existing: period.entry(item.date), suggested: hasAssignment(item.date)) }
            }
            .sheet(isPresented: $configure) {
                NavigationStack {
                    PayrollConfigurationView(period: period, opening: book.openingLeaveUnits[String(year)] ?? 0) { value, opening in
                        store.change { ledger in
                            try ledger.changePayroll("Cấu hình lương " + value.id) { book in
                                try book.put(value); book.openingLeaveUnits[String(year)] = opening
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $advance) { NavigationStack { SalaryAdvanceEditor(month: month) } }
            .sheet(item: $sharing) { DeliveryShareSheet(items: $0.items) }
            .alert("Chốt lương tháng này?", isPresented: $confirmClose) {
                Button("Chốt và giữ bản tính") { _ = store.change { try $0.closePayroll(month) } }
                Button("Hủy", role: .cancel) {}
            } message: { Text("Chỉ chốt từ ngày cuối tháng, khi đã đủ công và có giá xăng đúng ngày. Bản tính sẽ được giữ nguyên sau khi khóa.") }
            .alert("Lý do mở khóa", isPresented: $reopen) {
                TextField("Lý do điều chỉnh", text: $reason)
                Button("Mở khóa") { _ = store.change { try $0.reopenPayroll(month, reason: reason) } }
                Button("Hủy", role: .cancel) {}
            } message: { Text("Bản lương đã chốt vẫn lưu trong lịch sử; Sếp điều chỉnh rồi chốt thành bản mới.") }
    }
    private var calendar: some View {
        let days = PayrollDates.days(month)
        let offset = (PayrollDates.calendar.component(.weekday, from: days[0]) + 5) % 7
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
            ForEach(["T2", "T3", "T4", "T5", "T6", "T7", "CN"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
            ForEach(0..<(offset + days.count), id: \.self) { index in
                if index < offset { Color.clear.frame(height: 44) }
                else {
                    let date = days[index - offset], value = period.entry(date)?.state
                    Button { day = AttendanceDay(date: date) } label: {
                        VStack(spacing: 2) {
                            Text("\(PayrollDates.calendar.component(.day, from: date))").font(.subheadline.weight(.medium))
                            Text(value == .work ? "✓" : value == .half ? "½" : value == .leave ? "N" : value == .off ? "—" : hasAssignment(date) ? "•" : " ").font(.caption)
                        }.frame(maxWidth: .infinity, minHeight: 48)
                            .background(value == .work ? SweepStyle.green.opacity(0.2) : value == .leave ? Color.red.opacity(0.1) : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                        .disabled(closed != nil || date > PayrollDates.calendar.startOfDay(for: Date()) || store.busy || store.blocked)
                        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(value?.rawValue ?? "Chưa chấm")")
                        .accessibilityIdentifier("attendance.day.\(PayrollDates.calendar.component(.day, from: date))")
                }
            }
        }.padding(.vertical, 8)
    }
    private func summary(_ title: String, units value: Int) -> some View { VStack { Text(units(value)).font(.headline); Text(title).font(.caption).foregroundStyle(.secondary) } }
    private func units(_ n: Int) -> String { n % 2 == 0 ? String(n / 2) : String(format: "%.1f", Double(n) / 2) }
    private func move(_ step: Int) { month = PayrollDates.calendar.date(byAdding: .month, value: step, to: month)! }
    private func hasAssignment(_ day: Date) -> Bool {
        store.ledger.commissions(in: month, calendar: PayrollDates.calendar).contains { PayrollDates.calendar.isDate($0.1.signedAt, inSameDayAs: day) }
    }
    private func exportCSV() {
        func escape(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var csv = "\u{FEFF}Khoản,Số tiền (VND)\n"
        csv += result.rows.map { escape($0.0) + "," + String($0.1) }.joined(separator: "\n")
        csv += "\nTrạng thái," + (closed == nil ? "Tạm tính" : "Đã chốt") + "\nNgày,Công\n"
        csv += period.entries.sorted { $0.day < $1.day }.map { escape($0.day.formatted(date: .numeric, time: .omitted)) + "," + escape($0.state.rawValue) }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sweep-luong-\(period.id).csv")
        do { try csv.write(to: url, atomically: true, encoding: .utf8); sharing = DeliveryShare(items: [url]) } catch { store.message = error.localizedDescription }
    }
}

private struct AttendanceEditor: View {
    let day: Date
    let existing: AttendanceEntry?
    let suggested: Bool
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var state = AttendanceState.work
    @State private var note = ""
    var body: some View {
        Form {
            Section {
                Text(day.formatted(date: .complete, time: .omitted))
                Picker("Trạng thái", selection: $state) { ForEach(AttendanceState.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Ghi chú", text: $note)
                if suggested { Text("Ngày này có đơn đã ký. Sếp xác nhận công thực tế.").font(.footnote).foregroundStyle(.secondary) }
                Text("Nửa công tính 0,5 công và 0,5 ngày phép không lương; trợ cấp ngày hưởng một nửa.").font(.footnote).foregroundStyle(.secondary)
            }
            Button("Lưu công") { if store.change({ try $0.markAttendance(day, state: state, note: note) }) { dismiss() } }
                .accessibilityIdentifier("attendance.save")
            if existing != nil { Button("Bỏ chấm ngày này", role: .destructive) { if store.change({ try $0.markAttendance(day, state: nil) }) { dismiss() } } }
        }.navigationTitle("Chấm công").navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseSheet { dismiss() } }
            .onAppear { state = existing?.state ?? .work; note = existing?.note ?? "" }
    }
}

private struct PayrollConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @State var period: PayrollMonth
    let opening: Int
    let save: (PayrollMonth, Int) -> Bool
    @State private var base = ""
    @State private var phone = ""
    @State private var meal = ""
    @State private var maintenance = ""
    @State private var attendance = ""
    @State private var insurance = ""
    @State private var fuel = ""
    @State private var source = ""
    @State private var leave = ""
    @State private var adjustment = ""
    @State private var error = ""
    @State private var initialized = false
    var body: some View {
        Form {
            Section("Lịch làm việc chuẩn") {
                ForEach(1...7, id: \.self) { weekday in
                    Toggle(weekday == 1 ? "Chủ nhật" : "Thứ \(weekday)", isOn: Binding(get: { period.policy.weekdays.contains(weekday) }, set: { yes in
                        period.policy.weekdays.removeAll { $0 == weekday }; if yes { period.policy.weekdays.append(weekday) }
                    }))
                }
                Text("Ngày nghỉ theo lịch có thể chỉnh trên lịch chấm công; không trừ phép năm.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Mức tháng và trợ cấp ngày") {
                MoneyInput(title: "Lương cơ bản tháng", text: $base)
                MoneyInput(title: "Điện thoại tháng", text: $phone)
                MoneyInput(title: "Ăn / ngày", text: $meal)
                MoneyInput(title: "Bảo trì / ngày", text: $maintenance)
                MoneyInput(title: "Chuyên cần tháng", text: $attendance)
                MoneyInput(title: "Bảo hiểm tháng", text: $insurance)
                Stepper("\(period.policy.fuelLitres) lít xăng / ngày", value: $period.policy.fuelLitres, in: 0...20)
                Text("Lương cơ bản và điện thoại phân bổ theo công thực làm / công chuẩn. Nghỉ quá 3 ngày mất chuyên cần; bảo hiểm giữ mức tháng đã nhập.").font(.footnote).foregroundStyle(.secondary)
                Toggle("Đã kiểm tra lịch và mức tiền", isOn: $period.policy.confirmed)
            }
            Section("Giá xăng chốt của tháng") {
                TextField("Loại xăng công ty dùng", text: $period.policy.fuelType)
                TextField("Vùng giá", text: $period.policy.fuelRegion)
                Text("Ngày giá áp dụng: " + PayrollDates.fuelDay(period.month).formatted(date: .numeric, time: .omitted))
                MoneyInput(title: "Giá xăng / lít (để trống nếu chưa chốt)", text: $fuel)
                TextField("Nguồn giá / ghi nhận công ty", text: $source)
                Link("Đối chiếu Petrolimex", destination: URL(string: "https://www.petrolimex.com.vn/")!)
                Text("Nhập đúng giá có hiệu lực ngày chốt, không lấy giá hôm nay thay tháng cũ. Tự động lấy giá chưa được bật.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Phép năm và điều chỉnh") {
                TextField("Phép đã dùng trước dữ liệu công trong Sweep", text: $leave).keyboardType(.decimalPad)
                Text("Số ngày nghỉ không lương đã dùng trong năm ngoài các ngày đã chấm trong Sweep. Hạn mức 12 ngày.").font(.footnote).foregroundStyle(.secondary)
                TextField("Điều chỉnh lương, số âm để trừ", text: $adjustment).keyboardType(.numbersAndPunctuation)
                TextField("Lý do điều chỉnh", text: $period.adjustmentReason)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            Button("Lưu cấu hình") { persist() }.accessibilityIdentifier("payroll.saveConfiguration")
        }.navigationTitle("Cấu hình lương").navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseSheet { dismiss() } }
            .onAppear {
                guard !initialized else { return }; initialized = true
                let p = period.policy
                base = String(p.base); phone = String(p.phone); meal = String(p.meal); maintenance = String(p.maintenance)
                attendance = String(p.attendance); insurance = String(p.insurance)
                fuel = period.fuel.map { String($0.price) } ?? ""; source = period.fuel?.source ?? ""
                leave = String(Double(opening) / 2); adjustment = String(period.adjustment)
            }
    }
    private func persist() {
        do {
            var value = period
            value.policy.base = try VND.parse(base); value.policy.phone = try VND.parse(phone)
            value.policy.meal = try VND.parse(meal); value.policy.maintenance = try VND.parse(maintenance)
            value.policy.attendance = try VND.parse(attendance); value.policy.insurance = try VND.parse(insurance)
            guard let opening = Double(leave.replacingOccurrences(of: ",", with: ".")), opening.isFinite, opening >= 0, opening <= 366, (opening * 2).rounded() == opening * 2 else { throw DeliveryError.invalid("Phép đầu kỳ phải là số ngày hoặc nửa ngày hợp lệ.") }
            guard let delta = Int64(adjustment.trimmingCharacters(in: .whitespaces)) else { throw DeliveryError.invalid("Điều chỉnh phải là số nguyên đồng, có thể thêm dấu trừ.") }
            value.adjustment = delta
            if !fuel.trimmingCharacters(in: .whitespaces).isEmpty {
                guard PayrollDates.calendar.startOfDay(for: Date()) >= PayrollDates.fuelDay(period.month) else { throw DeliveryError.invalid("Chưa đến ngày chốt giá xăng của tháng. Để trống giá để lưu cấu hình trước.") }
                value.fuel = PayrollFuel(price: try VND.parse(fuel), effectiveDay: PayrollDates.fuelDay(period.month), source: source)
            } else { value.fuel = nil }
            try value.policy.validate()
            if save(value, Int(opening * 2)) { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}

private struct SalaryAdvanceEditor: View {
    let month: Date
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var note = ""
    @State private var day = Date()
    @State private var error = ""
    var body: some View {
        Form {
            DatePicker("Ngày tạm ứng", selection: $day, displayedComponents: .date)
            MoneyInput(title: "Số tiền đã ứng", text: $amount)
            TextField("Ghi chú", text: $note)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            Button("Ghi khoản tạm ứng") {
                do {
                    guard DeliveryMonth.contains(day, in: month), day <= Date() else { throw DeliveryError.invalid("Chọn ngày đã ứng trong tháng đang xem.") }
                    let item = SalaryAdvance(day: day, amount: try VND.parse(amount), note: note)
                    if store.change({ ledger in try ledger.changePayroll("Ghi tạm ứng") { book in var p = book.period(month); p.advances.append(item); try book.put(p) } }) { dismiss() }
                } catch { self.error = error.localizedDescription }
            }
        }.navigationTitle("Tạm ứng").toolbar { CloseSheet { dismiss() } }
            .onAppear { day = DeliveryMonth.contains(Date(), in: month) ? Date() : month }
    }
}
