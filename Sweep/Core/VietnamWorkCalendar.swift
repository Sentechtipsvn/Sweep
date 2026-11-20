import Foundation

struct WorkHolidayOptions: Codable, Equatable {
    var beforeTet = 2
    var nationalDayOffset = 0
    var compensateSunday = true
}

enum VietnamWorkCalendar {
    // Two Gregorian MMDD values per year (2000…2099): Tết and the tenth day
    // of the non-leap third month, from vnlunar 1.0.5's Vietnamese UTC+7 tables.
    private static let lunarDates: [(Int, Int)] = [
        (205, 414), (124, 403), (212, 422), (201, 411), (122, 428), // 2000–2004
        (209, 418), (129, 407), (217, 426), (207, 415), (126, 404), // 2005–2009
        (214, 423), (203, 412), (123, 331), (210, 419), (131, 409), // 2010–2014
        (219, 428), (208, 416), (128, 406), (216, 425), (205, 414), // 2015–2019
        (125, 402), (212, 421), (201, 410), (122, 429), (210, 418), // 2020–2024
        (129, 407), (217, 426), (206, 416), (126, 404), (213, 423), // 2025–2029
        (202, 412), (123, 401), (211, 419), (131, 409), (219, 428), // 2030–2034
        (208, 417), (128, 406), (215, 424), (204, 413), (124, 403), // 2035–2039
        (212, 420), (201, 410), (122, 429), (210, 419), (130, 407), // 2040–2044
        (217, 426), (206, 415), (126, 404), (214, 422), (202, 411), // 2045–2049
        (123, 401), (211, 420), (201, 409), (218, 428), (208, 417), // 2050–2054
        (128, 406), (215, 424), (204, 413), (124, 402), (212, 421), // 2055–2059
        (202, 410), (121, 331), (209, 419), (129, 408), (217, 426), // 2060–2064
        (205, 415), (126, 404), (214, 423), (203, 411), (123, 401), // 2065–2069
        (211, 420), (131, 409), (219, 427), (207, 416), (127, 405), // 2070–2074
        (215, 424), (205, 413), (124, 402), (212, 421), (202, 411), // 2075–2079
        (122, 330), (209, 418), (129, 407), (217, 426), (206, 414), // 2080–2084
        (126, 403), (214, 422), (203, 412), (124, 401), (210, 420), // 2085–2089
        (130, 409), (218, 428), (207, 416), (127, 405), (215, 424), // 2090–2094
        (205, 413), (125, 402), (212, 421), (201, 411), (121, 429), // 2095–2099
    ]

    static func daysOff(year: Int, options: WorkHolidayOptions, calendar: Calendar = DeliveryMonth.calendar) -> Set<Date> {
        func day(_ mmdd: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: mmdd / 100, day: mmdd % 100))!
        }
        func shifted(_ date: Date, _ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: date)!
        }
        var dates: Set<Date> = [day(101), day(430), day(501), day(902)]
        if [-1, 1].contains(options.nationalDayOffset) { dates.insert(shifted(day(902), options.nationalDayOffset)) }
        if lunarDates.indices.contains(year - 2000) {
            let (tet, hung) = lunarDates[year - 2000]
            dates.insert(day(hung))
            let before = min(3, max(1, options.beforeTet))
            for offset in 0..<5 { dates.insert(shifted(day(tet), offset - before)) }
        }
        if options.compensateSunday {
            for holiday in dates.sorted() where calendar.component(.weekday, from: holiday) == 1 {
                var next = shifted(holiday, 1)
                while dates.contains(next) || calendar.component(.weekday, from: next) == 1 { next = shifted(next, 1) }
                dates.insert(next)
            }
        }
        return dates
    }
}
