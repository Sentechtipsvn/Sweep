import Foundation

enum DeliveryPeriod: String, CaseIterable {
    case day = "Đã giao trong ngày", week = "Đã giao trong tuần", month = "Đã giao trong tháng"
    func contains(_ order: DeliveryOrder, now: Date) -> Bool {
        var calendar = DeliveryMonth.calendar; calendar.firstWeekday = 2; calendar.minimumDaysInFirstWeek = 4
        let component: Calendar.Component = self == .day ? .day : self == .week ? .weekOfYear : .month
        guard order.voidReason == nil, order.outcome == .delivered,
              let at = order.firstDeliveredAt,
              let interval = calendar.dateInterval(of: component, for: now) else { return false }
        return at >= interval.start && at < interval.end
    }
}
enum AttendanceReminderPolicy {
    static func needsEntry(_ ledger: DeliveryLedger, at date: Date) -> Bool {
        let calendar = DeliveryMonth.calendar
        guard calendar.component(.weekday, from: date) != 1 else { return false }
        let daysOff = VietnamWorkCalendar.daysOff(year: calendar.component(.year, from: date), options: ledger.settings.holidays ?? WorkHolidayOptions())
        guard !daysOff.contains(calendar.startOfDay(for: date)) else { return false }
        return ledger.payroll?.period(date).entry(date) == nil
    }
    static func showDot(_ ledger: DeliveryLedger, now: Date) -> Bool {
        let hour = DeliveryMonth.calendar.component(.hour, from: now)
        return hour >= 8 && hour < 17 && needsEntry(ledger, at: now)
    }
    static func dates(_ ledger: DeliveryLedger, now: Date) -> [Date] {
        let c = DeliveryMonth.calendar
        return (0..<30).compactMap { offset in
            guard let day = c.date(byAdding: .day, value: offset, to: c.startOfDay(for: now)),
                  let date = c.date(bySettingHour: 8, minute: 0, second: 0, of: day), date > now,
                  needsEntry(ledger, at: date) else { return nil }
            return date
        }
    }
}
struct DeliveryWorkItem: Identifiable {
    enum Kind { case report, payment, cash, attendance, sales }
    let id: String
    let title: String
    let detail: String
    let kind: Kind
    var orderID: UUID?
    var actionable: Bool { kind != .sales }
    static func items(_ ledger: DeliveryLedger, now: Date) -> [DeliveryWorkItem] {
        var result: [DeliveryWorkItem] = []
        for order in ledger.orders where order.voidReason == nil && order.outcome == .delivered {
            if order.requiresReport && !order.reportSent {
                let missing = order.missingEvidence()
                result.append(Self(id: "report-\(order.id)", title: missing.isEmpty ? "Chưa xác nhận gửi nhóm" : "Thiếu chứng từ", detail: order.code + " · " + order.displayCustomer + (missing.isEmpty ? "" : " · " + missing.map(\.rawValue).joined(separator: ", ")), kind: .report, orderID: order.id))
            }
            if order.remaining > 0 && order.settlement?.route != .freight && order.settlement?.route != .cashFull {
                result.append(Self(id: "payment-\(order.id)", title: "Khách còn hẹn chuyển khoản", detail: order.code + " · " + VND.format(order.remaining), kind: .payment, orderID: order.id))
            }
            if order.remaining > 0 && order.settlement?.route == .freight {
                result.append(Self(id: "sales-\(order.id)", title: "Bán hàng theo dõi tiền chành", detail: order.code + " · " + order.displayCustomer, kind: .sales, orderID: order.id))
            }
        }
        if ledger.cashHeld > 0 { result.append(Self(id: "cash", title: "Tiền mặt còn giữ", detail: VND.format(ledger.cashHeld) + " · gồm tiền từ ngày trước", kind: .cash)) }
        if DeliveryMonth.calendar.component(.hour, from: now) >= 8 && needsAttendance(ledger, now) {
            result.append(Self(id: "attendance", title: "Chưa chấm công hôm nay", detail: "Ghi nhận đi làm hoặc nghỉ theo thực tế", kind: .attendance))
        }
        return result
    }
    private static func needsAttendance(_ ledger: DeliveryLedger, _ now: Date) -> Bool { AttendanceReminderPolicy.needsEntry(ledger, at: now) }
}

extension DeliveryOrder {
    var firstDeliveredAt: Date? { settlements.first(where: { $0.outcome == .delivered })?.at }
}

enum ReportShareResult {
    static func sentToZalo(activity: String?, completed: Bool, failed: Bool) -> Bool {
        guard completed, !failed, let target = activity?.lowercased() else { return false }
        return target == "vn.com.vng.zingalo" || target.hasPrefix("vn.com.vng.zingalo.")
    }
}
