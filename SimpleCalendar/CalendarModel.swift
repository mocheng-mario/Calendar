import Foundation
import SwiftUI

@MainActor
final class CalendarModel: ObservableObject {
    private let defaults: UserDefaults
    private static let scheduleKey = "schedules"
    private static let legacyScheduleKey = "scheduledDates"

    @Published private(set) var today: Date
    @Published private(set) var selectedDate: Date
    @Published private(set) var schedules: [CalendarSchedule] {
        didSet { defaults.set(try? JSONEncoder().encode(schedules), forKey: Self.scheduleKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let today = CalendarDates.localDay(at: .now)
        self.today = today
        selectedDate = today
        if let data = defaults.data(forKey: Self.scheduleKey),
           let saved = try? JSONDecoder().decode([CalendarSchedule].self, from: data) {
            schedules = saved.sorted { $0.date < $1.date }
        } else {
            let oldDates = defaults.array(forKey: Self.legacyScheduleKey) as? [Date] ?? []
            let migrated = oldDates.sorted().map { CalendarSchedule(date: $0, title: "") }
            schedules = migrated
            if !migrated.isEmpty {
                defaults.set(try? JSONEncoder().encode(migrated), forKey: Self.scheduleKey)
            }
        }
    }

    var selectedYear: Int { CalendarDates.gregorian.component(.year, from: selectedDate) }

    var monthDayTitle: String {
        let calendar = CalendarDates.gregorian
        let month = calendar.component(.month, from: selectedDate)
        let day = calendar.component(.day, from: selectedDate)
        return String(format: "%02d-%02d", month, day)
    }

    func days(startingOn firstWeekday: Int) -> [CalendarDay] {
        let calendar = CalendarDates.gregorian
        guard let month = calendar.dateInterval(of: .month, for: selectedDate) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: month.start)
        let leadingDays = (weekday - firstWeekday + 7) % 7
        return (0..<42).compactMap { index in
            guard let date = calendar.date(
                byAdding: .day, value: index - leadingDays, to: month.start
            ) else { return nil }
            return CalendarDay(date: date, isCurrentMonth: date >= month.start && date < month.end)
        }
    }

    func select(_ date: Date) {
        selectedDate = date
    }

    func moveMonth(by offset: Int) {
        let calendar = CalendarDates.gregorian
        guard let currentMonth = calendar.dateInterval(of: .month, for: selectedDate),
              let nextMonth = calendar.date(byAdding: .month, value: offset, to: currentMonth.start) else { return }
        selectMatchingDay(inMonthStartingAt: nextMonth)
    }

    func goToYear(_ year: Int) {
        guard (1...9999).contains(year), year != selectedYear else { return }
        let calendar = CalendarDates.gregorian
        let month = calendar.component(.month, from: selectedDate)
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return }
        selectMatchingDay(inMonthStartingAt: start)
    }

    private func selectMatchingDay(inMonthStartingAt month: Date) {
        let calendar = CalendarDates.gregorian
        guard let lastDay = calendar.range(of: .day, in: .month, for: month)?.last else { return }
        let day = min(calendar.component(.day, from: selectedDate), lastDay)
        if let date = calendar.date(byAdding: .day, value: day - 1, to: month) {
            select(date)
        }
    }

    func goToToday() {
        refreshToday(at: .now)
        select(today)
    }

    func refreshToday(at now: Date) {
        let newToday = CalendarDates.localDay(at: now)
        guard newToday != today else { return }
        let wasViewingToday = selectedDate == today
        today = newToday
        if wasViewingToday {
            select(newToday)
        }
    }

    func scheduleDraft(for day: Date) -> Date {
        let now = Date.now
        let calendar = CalendarDates.localGregorian
        if day == CalendarDates.localDay(at: now), let minute = calendar.dateInterval(of: .minute, for: now) {
            return CalendarDates.localDay(at: minute.end) == day ? minute.end : minute.start
        }
        var date = CalendarDates.gregorian.dateComponents([.year, .month, .day], from: day)
        date.hour = 9
        return calendar.date(from: date) ?? now
    }

    func hasSchedule(at date: Date, title: String) -> Bool {
        let minute = scheduleMinute(for: date)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return schedules.contains { $0.date == minute && $0.title == title }
    }

    func addSchedule(at date: Date, title: String) {
        guard !hasSchedule(at: date, title: title) else { return }
        let schedule = CalendarSchedule(date: scheduleMinute(for: date), title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        let index = schedules.firstIndex { $0.date > schedule.date } ?? schedules.endIndex
        schedules.insert(schedule, at: index)
    }

    func removeSchedule(_ id: UUID) {
        schedules.removeAll { $0.id == id }
    }

    private func scheduleMinute(for date: Date) -> Date {
        CalendarDates.localGregorian.dateInterval(of: .minute, for: date)?.start ?? date
    }
}

struct CalendarSchedule: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let title: String

    var displayTitle: String { title.isEmpty ? "未命名日程" : title }
}

struct CalendarDay: Identifiable {
    static let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    let date: Date
    let isCurrentMonth: Bool
    let month: Int
    let day: Int
    let weekday: Int
    let lunarDate: LunarDate?

    init(date: Date, isCurrentMonth: Bool) {
        let calendar = CalendarDates.gregorian
        self.date = date
        self.isCurrentMonth = isCurrentMonth
        month = calendar.component(.month, from: date)
        day = calendar.component(.day, from: date)
        weekday = calendar.component(.weekday, from: date)
        lunarDate = LunarDate(date: date)
    }

    var id: Date { date }
    var weekdayName: String { Self.weekdayNames[weekday - 1] }
    var isWeekend: Bool { weekday == 1 || weekday == 7 }

    func festival(solarTerm: String? = nil) -> Festival? {
        if solarTerm == "清明" { return .qingming }
        guard let lunarDate, !lunarDate.isLeapMonth else { return nil }
        switch (lunarDate.month, lunarDate.day) {
        case (1, 1): return .springFestival
        case (1, 15): return .lanternFestival
        case (5, 5): return .dragonBoatFestival
        case (8, 15): return .midAutumnFestival
        case (12, 29...30) where LunarDate.isNewYearsEve(on: date): return .springFestivalEve
        default: return nil
        }
    }
}

struct LunarDate {
    private static let zodiacSigns = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
    private static let months = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]
    private static let days = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    let month: Int
    let day: Int
    let isLeapMonth: Bool
    let zodiac: String?

    init?(date: Date) {
        let components = CalendarDates.chinese.dateComponents(in: CalendarDates.beijingTime, from: date)
        guard let month = components.month, (1...Self.months.count).contains(month),
              let day = components.day, (1...Self.days.count).contains(day) else { return nil }
        self.month = month
        self.day = day
        isLeapMonth = components.isLeapMonth == true
        zodiac = components.year.flatMap { $0 > 0 ? Self.zodiacSigns[($0 - 1) % Self.zodiacSigns.count] : nil }
    }

    var monthName: String { (isLeapMonth ? "闰" : "") + Self.months[month - 1] }
    var dayName: String { Self.days[day - 1] }
    var gridLabel: String { day == 1 ? monthName : dayName }

    static func isNewYearsEve(on date: Date) -> Bool {
        guard let tomorrow = CalendarDates.gregorian.date(byAdding: .day, value: 1, to: date),
              let lunar = LunarDate(date: tomorrow) else { return false }
        return lunar.month == 1 && lunar.day == 1 && !lunar.isLeapMonth
    }
}

enum Festival {
    case springFestival
    case springFestivalEve
    case qingming
    case lanternFestival
    case dragonBoatFestival
    case midAutumnFestival

    var name: String {
        switch self {
        case .springFestival: return "春节"
        case .springFestivalEve: return "除夕"
        case .qingming: return "清明节"
        case .lanternFestival: return "元宵节"
        case .dragonBoatFestival: return "端午节"
        case .midAutumnFestival: return "中秋节"
        }
    }

    var symbol: String {
        switch self {
        case .springFestival, .springFestivalEve, .lanternFestival: return "sparkles"
        case .qingming: return "leaf"
        case .dragonBoatFestival: return "leaf.fill"
        case .midAutumnFestival: return "moon.stars.fill"
        }
    }
}

enum CalendarDates {
    static let beijingTime = TimeZone(secondsFromGMT: 8 * 60 * 60)!
    static let gregorian = makeCalendar(.gregorian)
    static let chinese = makeCalendar(.chinese)

    static var localGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private static func makeCalendar(_ identifier: Calendar.Identifier) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = beijingTime
        return calendar
    }

    static func localDay(at now: Date, in timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        // 按本地公历年月日查对应农历，避免在海外因时差把节日标到前一天或后一天。
        let local = gregorian.dateComponents(in: timeZone, from: now)
        let date = DateComponents(year: local.year, month: local.month, day: local.day)
        return gregorian.date(from: date) ?? gregorian.startOfDay(for: now)
    }

    static func parseDay(_ value: String) -> Date? {
        let fields = value.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0].count == 4, fields[1].count == 2, fields[2].count == 2,
              fields.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(fields[0]), year > 0, let month = Int(fields[1]), let day = Int(fields[2]) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: gregorian) else { return nil }
        return gregorian.date(from: components)
    }
}
