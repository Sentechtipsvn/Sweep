import Foundation

enum DeliveryMonth {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return value
    }
    static func start(_ date: Date) -> Date { calendar.dateInterval(of: .month, for: date)!.start }
    static func contains(_ date: Date, in month: Date) -> Bool {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return false }
        return date >= interval.start && date < interval.end
    }
    static func rollover(selected: Date, observed: Date, now: Date) -> Date {
        start(observed) == start(now) ? selected : start(now)
    }
}

struct MonthlyReconciliation {
    let month: Date
    let commissions: [(DeliveryOrder, SignedAssignment)]
    let orders: [DeliveryOrder]
    let handovers: [CashHandover]
    let validHandovers: [CashHandover]
    var count: Int { commissions.count }
    var fee: Int64 { commissions.reduce(0) { $0 + $1.1.fee } }
    var cashCollected: Int64 { orders.reduce(0) { $0 + $1.cash } }
    var cashHanded: Int64 { validHandovers.reduce(0) { $0 + $1.amount } }
    var cashDifference: Int64 { cashCollected - cashHanded }
    var bankPending: Int64 { orders.reduce(0) { $0 + $1.bank - $1.verifiedBank } }
    var pendingOrders: [DeliveryOrder] { orders.filter { $0.bank > $0.verifiedBank } }

    init(ledger: DeliveryLedger, month: Date) {
        self.month = DeliveryMonth.start(month)
        commissions = ledger.commissions(in: month, calendar: DeliveryMonth.calendar).sorted { $0.1.signedAt < $1.1.signedAt }
        orders = ledger.orders.filter { order in order.settlement.map { DeliveryMonth.contains($0.at, in: month) } ?? false }
        handovers = ledger.handovers.filter { DeliveryMonth.contains($0.at, in: month) }.sorted { $0.at > $1.at }
        let reversed = Set(ledger.handoverReversals.map(\.handoverID))
        validHandovers = handovers.filter { !reversed.contains($0.id) }
    }
}
