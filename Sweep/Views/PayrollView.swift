import SwiftUI

private struct AttendanceDay: Identifiable { let date: Date; var id: Date { date } }

/// A single calculation per screen update; calendar cells never rescan the ledger.
private struct PayrollScreenData {
    let month: Date
    let book: PayrollBook
    let period: PayrollMonth
    let closed: PayrollSnapshot?
    let result: PayrollCalculation
    let signedDays: Set<Date>
    var year: Int { PayrollDates.calendar.component(.year, from: month) }
    init(ledger: DeliveryLedger, month: Date) {
        self.month = month
        let book = ledger.payroll ?? PayrollBook()
        self.book = book
        period = book.period(month)
        closed = book.closed(month)
        result = closed?.calculation ?? PayrollCalculation(ledger: ledger, period: period)
        signedDays = Set(ledger.commissions(in: month, calendar: PayrollDates.calendar).map { PayrollDates.calendar.startOfDay(for: $0.1.signedAt) })
    }
}
private func payrollUnits(_ value: Int) -> String {
    value % 2 == 0 ? String(value / 2) : String(format: "%.1f", Double(value) / 2)
}

struct PayrollView: View {
    private enum Confirmation { case close, reopen }
    @EnvironmentObject private var store: DeliveryStore
    @State private var month = DeliveryMonth.start(Date())
    @State private var day: AttendanceDay?
    @State private var configure = false
    @State private var advance = false
    @State private var confirmation: Confirmation?
    @State private var reason = ""
    @State private var sharing: DeliveryShare?
    var body: some View {
        let data = PayrollScreenData(ledger: store.ledger, month: month)
        PayrollContent(data: data, canEdit: !store.busy && !store.blocked, storageIssue: store.blocked ? store.storageIssue : nil,
                       selectDay: { day = AttendanceDay(date: $0) }, move: move,
                       configure: { configure = true }, advance: { advance = true },
                       close: { confirmation = .close }, reopen: { reason = ""; confirmation = .reopen },
                       export: { exportCSV(data) })
            .sendeliNavigationTitle("Chấm công & lương").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { configure = true } label: { Image(systemName: "slider.horizontal.3") }
                        .disabled(data.closed != nil || store.busy || store.blocked).accessibilityLabel("Cấu hình lương")
                }
            }
            .sheet(item: $day) { item in
                NavigationStack {
                    AttendanceEditor(day: item.date, existing: data.period.entry(item.date), suggested: data.signedDays.contains(item.date))
                }
            }
            .sheet(isPresented: $configure) {
                NavigationStack {
                    PayrollConfigurationView(period: data.period, opening: data.book.openingLeaveUnits[String(data.year)] ?? 0) { value, opening in
                        store.change { ledger in
                            try ledger.changePayroll("Cấu hình lương " + value.id) { book in
                                try book.put(value); book.openingLeaveUnits[String(data.year)] = opening
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $advance) { NavigationStack { SalaryAdvanceEditor(month: month) } }
            .sheet(item: $sharing) { DeliveryShareSheet(items: $0.items) }
            .alert(confirmation == .reopen ? "Lý do mở khóa" : "Chốt lương tháng này?",
                   isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), presenting: confirmation) { value in
                if value == .reopen {
                    TextField("Lý do điều chỉnh", text: $reason)
                    Button("Mở khóa") { _ = store.change { try $0.reopenPayroll(month, reason: reason) } }
                } else {
                    Button("Chốt và giữ bản tính") { _ = store.change { try $0.closePayroll(month) } }
                }
                Button("Hủy", role: .cancel) {}
            } message: { value in
                Text(value == .reopen ? "Bản lương đã chốt vẫn lưu trong lịch sử; Sếp điều chỉnh rồi chốt thành bản mới." : "Chỉ chốt từ ngày cuối tháng, khi đã đủ công và có giá xăng đúng ngày. Bản tính sẽ được giữ nguyên sau khi khóa.")
            }
    }
    private func move(_ step: Int) {
        guard let next = PayrollDates.calendar.date(byAdding: .month, value: step, to: month),
              (1900...2299).contains(PayrollDates.calendar.component(.year, from: next)) else { return }
        month = next
    }
    private func exportCSV(_ data: PayrollScreenData) {
        func escape(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var csv = "\u{FEFF}Khoản,Số tiền (VND)\n"
        csv += data.result.rows.map { escape($0.0) + "," + (!data.period.policy.confirmed ? "Chưa cấu hình" : $0.0 == "Xăng xe" && !data.result.fuelConfirmed ? "Chờ chốt giá" : String($0.1)) }.joined(separator: "\n")
        csv += "\nTrạng thái," + (data.closed == nil ? "Tạm tính" : "Đã chốt") + "\nNgày,Công\n"
        csv += data.period.entries.sorted { $0.day < $1.day }.map { escape($0.day.formatted(date: .numeric, time: .omitted)) + "," + escape($0.state.rawValue) }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sweep-luong-\(data.period.id).csv")
        do { try csv.write(to: url, atomically: true, encoding: .utf8); sharing = DeliveryShare(items: [url]) } catch { store.message = error.localizedDescription }
    }
}

/// Keep each section a separate view to bound SwiftUI's generated layout and stack use.
private struct PayrollContent: View {
    let data: PayrollScreenData
    let canEdit: Bool
    let storageIssue: String?
    let selectDay: (Date) -> Void
    let move: (Int) -> Void
    let configure: () -> Void
    let advance: () -> Void
    let close: () -> Void
    let reopen: () -> Void
    let export: () -> Void
    var body: some View {
        SweepGroupedScroll {
            if let storageIssue {
                SweepCard {
                    Label("Sổ đang ở chế độ chỉ đọc", systemImage: "lock.fill").foregroundStyle(.orange)
                    Text(storageIssue).font(.footnote)
                }
            }
            PayrollSummarySection(data: data, move: move)
            SweepCard(title: "Chấm công") {
                PayrollCalendar(period: data.period, signedDays: data.signedDays, canEdit: canEdit && data.closed == nil, select: selectDay)
            }
            PayrollLeaveSection(data: data)
            PayrollSalarySection(data: data)
            PayrollAdvancesSection(period: data.period, canEdit: canEdit && data.closed == nil, add: advance)
            SweepCard {
                if data.closed == nil {
                    Button("Cấu hình lương và giá xăng", systemImage: "slider.horizontal.3", action: configure).disabled(!canEdit).accessibilityIdentifier("payroll.configure")
                    Button("Chốt bảng lương tháng", systemImage: "lock", action: close).disabled(!canEdit).accessibilityIdentifier("payroll.close")
                } else {
                    Button("Mở khóa để điều chỉnh", systemImage: "lock.open", action: reopen).disabled(!canEdit)
                }
                Button("Xuất bảng lương CSV", systemImage: "square.and.arrow.up", action: export)
            }
            SweepCard {
                Text("Chấm công thủ công; đơn đã ký chỉ gợi ý ngày đi làm. Tiền thu hộ không cộng vào lương. Mức tiền và lịch làm việc áp dụng theo cấu hình tháng.").font(.footnote).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("payroll.content")
    }
}
private struct PayrollSummarySection: View {
    let data: PayrollScreenData
    let move: (Int) -> Void
    var body: some View {
        SweepCard {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless).accessibilityLabel("Tháng trước").accessibilityIdentifier("payroll.previous")
                Spacer()
                Text(verbatim: "Tháng \(PayrollDates.calendar.component(.month, from: data.month)) / \(data.year)").font(.headline)
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless).accessibilityLabel("Tháng sau").accessibilityIdentifier("payroll.next")
            }
            Label(data.closed == nil ? "Lương tạm tính" : "Bảng lương đã chốt", systemImage: data.closed == nil ? "clock" : "lock.fill")
                .font(.caption).foregroundStyle(data.closed == nil ? Color.secondary : Color.green)
            Text(data.period.policy.confirmed ? VND.format(data.result.net) : "Chưa cấu hình lương")
                .font(.system(data.period.policy.confirmed ? .largeTitle : .title2, design: .rounded, weight: .bold)).monospacedDigit().accessibilityIdentifier("payroll.net")
            HStack {
                summary("Công", value: payrollUnits(data.result.workUnits))
                Spacer()
                summary("Nghỉ", value: payrollUnits(data.result.leaveUnits))
                Spacer()
                summary("Đơn", value: String(data.result.commissions))
            }
            if !data.period.policy.confirmed { Label("Chọn lịch làm việc và xác nhận mức lương trước khi chốt.", systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange) }
            if data.result.missingDays > 0 { Text("\(data.result.missingDays) ngày làm việc chưa chấm; ngày trống không tự coi là nghỉ.").font(.footnote).foregroundStyle(.secondary) }
        }
    }
    private func summary(_ title: String, value: String) -> some View {
        VStack { Text(value).font(.headline); Text(title).font(.caption).foregroundStyle(.secondary) }
    }
}
private struct PayrollLeaveSection: View {
    let data: PayrollScreenData
    var body: some View {
        let used = data.book.annualLeaveUnits(year: data.year)
        let remaining = 24 - used
        SweepCard(title: "Phép năm " + String(data.year)) {
            LabeledContent("Đã nghỉ / hạn mức", value: "\(payrollUnits(used)) / 12 ngày")
            Text(remaining < 0 ? "Vượt \(payrollUnits(-remaining)) ngày. Vẫn giữ toàn bộ ngày nghỉ để đối chiếu." : "Còn \(payrollUnits(remaining)) ngày phép không lương.")
                .font(.footnote).foregroundStyle(remaining < 0 ? Color.red : Color.secondary)
            Text("Nghỉ quá 3 ngày/tháng mất chuyên cần. Đúng 3 ngày vẫn giữ.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
private struct PayrollSalarySection: View {
    let data: PayrollScreenData
    var body: some View {
        SweepCard(title: "Các khoản tháng này") {
            ForEach(data.result.rows, id: \.0) { label, value in
                LabeledContent(label, value: !data.period.policy.confirmed ? "Chưa cấu hình" : label == "Xăng xe" && !data.result.fuelConfirmed ? "Chờ chốt giá" : VND.format(value))
            }
            LabeledContent("Công chuẩn", value: payrollUnits(data.result.plannedUnits) + " ngày")
            LabeledContent("Chốt lương", value: PayrollDates.closeDay(data.month).formatted(date: .numeric, time: .omitted))
            LabeledContent("Ngày chốt giá xăng", value: PayrollDates.fuelDay(data.month).formatted(date: .numeric, time: .omitted))
            if let fuel = data.period.fuel {
                Text("\(fuel.price)₫/lít · \(fuel.source)").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Giá ngày 30 áp dụng cho cả tháng; tháng 2 dùng ngày cuối tháng. Không có giá đúng thì để chờ chốt.").font(.footnote).foregroundStyle(.orange)
            }
        }
    }
}
private struct PayrollAdvancesSection: View {
    let period: PayrollMonth
    let canEdit: Bool
    let add: () -> Void
    var body: some View {
        SweepCard(title: "Tạm ứng") {
            ForEach(period.advances) { item in
                VStack(alignment: .leading) {
                    LabeledContent(item.day.formatted(date: .numeric, time: .omitted), value: VND.format(item.amount))
                    if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if canEdit { Button("Thêm khoản tạm ứng", systemImage: "plus.circle", action: add) }
        }
    }
}
private struct PayrollCalendar: View {
    let period: PayrollMonth
    let signedDays: Set<Date>
    let canEdit: Bool
    let select: (Date) -> Void
    var body: some View {
        let days = PayrollDates.days(period.month)
        if let first = days.first {
            let offset = (PayrollDates.calendar.component(.weekday, from: first) + 5) % 7
            let rowCount = (offset + days.count + 6) / 7
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(["T2", "T3", "T4", "T5", "T6", "T7", "CN"], id: \.self) { title in
                        Text(title).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column - offset
                            if days.indices.contains(index) {
                                let date = days[index]
                                AttendanceDayButton(date: date, state: period.entry(date)?.state, suggested: signedDays.contains(date),
                                                    enabled: canEdit && date <= PayrollDates.calendar.startOfDay(for: Date())) { select(date) }
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 48).accessibilityHidden(true)
                            }
                        }
                    }
                }
            }.padding(.vertical, 8)
        }
    }
}
private struct AttendanceDayButton: View {
    let date: Date
    let state: AttendanceState?
    let suggested: Bool
    let enabled: Bool
    let select: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var marker: String {
        switch state {
        case .work: return "✓"
        case .half: return "½"
        case .leave: return "N"
        case .off: return "—"
        case nil: return suggested ? "•" : " "
        }
    }
    var body: some View {
        Button(action: select) {
            VStack(spacing: 2) {
                Text("\(PayrollDates.calendar.component(.day, from: date))").font(.subheadline.weight(.medium))
                Text(marker).font(.caption).id(marker)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }.frame(maxWidth: .infinity, minHeight: 48)
                .background(state == .work ? SweepStyle.green.opacity(0.2) : state == .leave ? Color.red.opacity(0.1) : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(SweepDayPress()).disabled(!enabled)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.75), value: state)
            .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(state?.rawValue ?? "Chưa chấm")")
            .accessibilityIdentifier("attendance.day.\(PayrollDates.calendar.component(.day, from: date))")
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
        SweepGroupedScroll {
            SweepCard {
                Text(day.formatted(date: .complete, time: .omitted))
                Picker("Trạng thái", selection: $state) { ForEach(AttendanceState.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                TextField("Ghi chú", text: $note)
                if suggested { Text("Ngày này có đơn đã ký. Sếp xác nhận công thực tế.").font(.footnote).foregroundStyle(.secondary) }
                Text("Nửa công tính 0,5 công và 0,5 ngày phép không lương; trợ cấp ngày hưởng một nửa.").font(.footnote).foregroundStyle(.secondary)
            }
            Button("Lưu công") { if store.change({ try $0.markAttendance(day, state: state, note: note) }) { dismiss() } }
                .accessibilityIdentifier("attendance.save")
            if existing != nil { Button("Bỏ chấm ngày này", role: .destructive) { if store.change({ try $0.markAttendance(day, state: nil) }) { dismiss() } } }
        }.sendeliNavigationTitle("Chấm công").navigationBarTitleDisplayMode(.inline)
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
        SweepGroupedScroll {
            SweepCard(title: "Lịch làm việc chuẩn") {
                ForEach(1...7, id: \.self) { weekday in
                    Toggle(weekday == 1 ? "Chủ nhật" : "Thứ \(weekday)", isOn: Binding(get: { period.policy.weekdays.contains(weekday) }, set: { yes in
                        period.policy.weekdays.removeAll { $0 == weekday }; if yes { period.policy.weekdays.append(weekday) }
                    }))
                }
                Text("Ngày nghỉ theo lịch có thể chỉnh trên lịch chấm công; không trừ phép năm.").font(.footnote).foregroundStyle(.secondary)
            }
            SweepCard(title: "Mức tháng và trợ cấp ngày") {
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
            SweepCard(title: "Giá xăng chốt của tháng") {
                TextField("Loại xăng công ty dùng", text: $period.policy.fuelType)
                TextField("Vùng giá", text: $period.policy.fuelRegion)
                Text("Ngày giá áp dụng: " + PayrollDates.fuelDay(period.month).formatted(date: .numeric, time: .omitted))
                MoneyInput(title: "Giá xăng / lít", text: $fuel)
                TextField("Nguồn giá / ghi nhận công ty", text: $source)
                Link("Đối chiếu Petrolimex", destination: URL(string: "https://www.petrolimex.com.vn/")!)
                Text("Nhập đúng giá có hiệu lực ngày chốt, không lấy giá hôm nay thay tháng cũ. Tự động lấy giá chưa được bật.").font(.footnote).foregroundStyle(.secondary)
            }
            SweepCard(title: "Phép năm và điều chỉnh") {
                TextField("Phép đã dùng trước dữ liệu công trong Sendeli", text: $leave).keyboardType(.decimalPad)
                Text("Số ngày nghỉ không lương đã dùng trong năm ngoài các ngày đã chấm trong Sendeli. Hạn mức 12 ngày.").font(.footnote).foregroundStyle(.secondary)
                TextField("Điều chỉnh lương, số âm để trừ", text: $adjustment).keyboardType(.numbersAndPunctuation)
                TextField("Lý do điều chỉnh", text: $period.adjustmentReason)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            Button("Lưu cấu hình") { persist() }.accessibilityIdentifier("payroll.saveConfiguration")
        }.sendeliNavigationTitle("Cấu hình lương").navigationBarTitleDisplayMode(.inline)
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
        SweepGroupedScroll {
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
        }.sendeliNavigationTitle("Tạm ứng").toolbar { CloseSheet { dismiss() } }
            .onAppear { day = DeliveryMonth.contains(Date(), in: month) ? Date() : month }
    }
}
