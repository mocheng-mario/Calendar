import Foundation

private final class CalendarDataResources: NSObject {
    static let bundle = Bundle(for: CalendarDataResources.self)
}

struct CalendarOccasion {
    let date: Date
    let name: String
}

struct HolidayDay {
    let date: Date
    let name: String
    let isOffDay: Bool
}

struct HolidayYear: Decodable {
    let year: Int
    let days: [HolidayDay]

    private enum CodingKeys: String, CodingKey { case year, days }

    private struct Record: Decodable {
        let date: String
        let name: String
        let isOffDay: Bool
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        year = try container.decode(Int.self, forKey: .year)
        let records = try container.decode([Record].self, forKey: .days)
        guard (1900...9999).contains(year), !records.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .days, in: container, debugDescription: "年份无效或缺少假期记录。")
        }

        var dates = Set<Date>()
        days = try records.map { record in
            let name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let date = CalendarDates.parseDay(record.date), dates.insert(date).inserted else {
                throw DecodingError.dataCorruptedError(forKey: .days, in: container, debugDescription: "假期名称为空，或日期无效、重复：\(record.date)")
            }
            return HolidayDay(date: date, name: name, isOffDay: record.isOffDay)
        }
    }
}

struct HolidayCalendar {
    let years: [Int]
    var solarTerms = SolarTerms.bundled
    private let documents: [HolidayYear]
    private let days: [Date: HolidayDay]

    init(documents: [HolidayYear]) {
        self.documents = documents
        years = documents.map(\.year).sorted()
        days = Dictionary(documents.flatMap(\.days).map { ($0.date, $0) }, uniquingKeysWith: { _, higherPriority in higherPriority })
    }

    func replacingYears(with other: HolidayCalendar) -> HolidayCalendar {
        if other.years.isEmpty { return self }
        var combined = HolidayCalendar(documents: documents.filter { !other.years.contains($0.year) } + other.documents)
        combined.solarTerms = solarTerms
        return combined
    }

    subscript(date: Date) -> HolidayDay? {
        if let day = days[date] { return day }
        guard let occasion = statutoryOccasion(on: date) else { return nil }
        return HolidayDay(date: date, name: occasion.name, isOffDay: true)
    }

    func statutoryOccasion(on date: Date) -> CalendarOccasion? {
        let isOffDay = days[date]?.isOffDay ?? !covers(date)
        guard isOffDay, let name = StatutoryHolidays.name(on: date, solarTerm: solarTerms.name(on: date)) else { return nil }
        return CalendarOccasion(date: date, name: name)
    }

    func nextStatutoryDay(from date: Date) -> CalendarOccasion? {
        for offset in 0...366 {
            guard let day = CalendarDates.gregorian.date(byAdding: .day, value: offset, to: date) else { break }
            if let occasion = statutoryOccasion(on: day) { return occasion }
        }
        return nil
    }

    func covers(_ date: Date) -> Bool {
        years.contains(CalendarDates.gregorian.component(.year, from: date))
    }

    static let bundled: HolidayCalendar = {
        guard let directory = CalendarDataResources.bundle.resourceURL?.appendingPathComponent("CalendarData/holiday-cn", isDirectory: true) else {
            return HolidayCalendar(documents: [])
        }
        return HolidayCalendar(directory: directory)
    }()

    init(directory: URL) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let documents = urls.compactMap { url -> HolidayYear? in
            guard url.pathExtension == "json", let year = Int(url.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: url), let calendar = try? JSONDecoder().decode(HolidayYear.self, from: data),
                  calendar.year == year else { return nil }
            return calendar
        }
        self.init(documents: documents.sorted { $0.year < $1.year })
    }
}

struct SolarTerms {
    static let supportedYears = 1901...2100
    private static let names: Set<String> = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
        "小暑", "大暑", "立秋", "处暑", "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]
    private static let traditionalNames = ["驚蟄": "惊蛰", "穀雨": "谷雨", "小滿": "小满", "芒種": "芒种", "處暑": "处暑"]

    let years: Set<Int>
    private let terms: [CalendarOccasion]
    private let byDate: [Date: String]

    init(terms: [CalendarOccasion]) {
        self.terms = terms.sorted { $0.date < $1.date }
        years = Set(terms.map { CalendarDates.gregorian.component(.year, from: $0.date) })
        byDate = Dictionary(terms.map { ($0.date, $0.name) }, uniquingKeysWith: { _, newer in newer })
    }

    static let bundled: SolarTerms = {
        guard let url = CalendarDataResources.bundle.url(forResource: "solar-terms", withExtension: "csv", subdirectory: "CalendarData"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return SolarTerms(terms: []) }
        let terms = contents.split(whereSeparator: \.isNewline).compactMap { line -> CalendarOccasion? in
            let fields = line.split(separator: ",", maxSplits: 1)
            guard fields.count == 2, let date = CalendarDates.parseDay(String(fields[0])) else { return nil }
            return CalendarOccasion(date: date, name: String(fields[1]))
        }
        return SolarTerms(terms: terms)
    }()

    static func cached(in directory: URL) -> SolarTerms {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let terms = files.flatMap { file -> [CalendarOccasion] in
            guard file.pathExtension == "txt", let year = Int(file.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: file) else { return [] }
            return parseObservatoryTable(data, year: year) ?? []
        }
        return bundled.adding(terms)
    }

    static func parseObservatoryTable(_ data: Data, year: Int) -> [CalendarOccasion]? {
        guard supportedYears.contains(year), let text = String(data: data, encoding: .utf8) else { return nil }
        let terms = text.split(whereSeparator: \.isNewline).compactMap { line -> CalendarOccasion? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 4, fields[2].hasPrefix("星期") else { return nil }
            let parts = fields[0].split { "年月日".contains($0) }
            let label = String(fields[3])
            let name = traditionalNames[label] ?? label
            guard names.contains(name), parts.count == 3, Int(parts[0]) == year,
                  let month = Int(parts[1]), let day = Int(parts[2]),
                  let date = CalendarDates.parseDay(String(format: "%04d-%02d-%02d", year, month, day)) else { return nil }
            return CalendarOccasion(date: date, name: name)
        }
        guard terms.count == names.count, Set(terms.map(\.name)) == names,
              Set(terms.map(\.date)).count == names.count else { return nil }
        return terms
    }

    func adding(_ entries: [CalendarOccasion]) -> SolarTerms {
        let newYears = Set(entries.map { CalendarDates.gregorian.component(.year, from: $0.date) })
        return SolarTerms(terms: terms.filter { !newYears.contains(CalendarDates.gregorian.component(.year, from: $0.date)) } + entries)
    }

    func name(on date: Date) -> String? { byDate[date] }

    func next(from date: Date) -> CalendarOccasion? {
        let calendar = CalendarDates.gregorian
        let year = calendar.component(.year, from: date)
        guard years.contains(year), let next = terms.first(where: { $0.date >= date }),
              calendar.component(.year, from: next.date) <= year + 1 else { return nil }
        return next
    }
}

private enum StatutoryHolidays {
    // 按国务院令第270、513、644、795号的生效年份区分法定日期；isOffDay 包含完整放假区间。
    static func name(on date: Date, solarTerm: String?) -> String? {
        let calendar = CalendarDates.gregorian
        let civil = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = civil.year, year >= 2007, let month = civil.month, let day = civil.day else { return nil }

        let laborDays = year < 2008 ? 3 : (year >= 2025 ? 2 : 1)
        let springStartsAtEve = (2008...2013).contains(year) || year >= 2025
        let lastSpringDay = (2008...2013).contains(year) ? 2 : 3
        var names: [String] = []
        switch (month, day) {
        case (1, 1): names.append("元旦")
        case (5, 1...laborDays): names.append("劳动节")
        case (10, 1...3): names.append("国庆节")
        default: break
        }
        if year >= 2008, solarTerm == "清明" { names.append("清明节") }

        if let lunar = LunarDate(date: date), !lunar.isLeapMonth {
            switch (lunar.month, lunar.day) {
            case (1, 1...lastSpringDay): names.append("春节")
            case (5, 5) where year >= 2008: names.append("端午节")
            case (8, 15) where year >= 2008: names.append("中秋节")
            default: break
            }
        }
        if springStartsAtEve, LunarDate.isNewYearsEve(on: date) {
            names.append("春节")
        }
        return names.isEmpty ? nil : names.joined(separator: "、")
    }
}
