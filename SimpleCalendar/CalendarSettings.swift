import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class CalendarSettings: ObservableObject {
    private enum Key {
        static let theme = "themeColor"
        static let popoverLayout = "popoverLayout"
        static let firstWeekday = "firstWeekday"
        static let clockFields = "clockFields"
        static let legacyClockFormat = "clockFormat"
        static let customClockFormat = "customClockFormat"
        static let holidaySources = "holidaySources"
        static let legacyHolidaySource = "holidaySource"
        static let legacyHolidayFiles = "importedHolidayFiles"
        static let holidayRefreshAttempts = "holidayRefreshAttempts"
        static let solarTermRefreshAttempts = "solarTermRefreshAttempts"
    }

    private let defaults: UserDefaults
    private let cacheDirectory: URL?
    private let solarTermCacheDirectory: URL?
    private let leadingClockFormatter = ClockField.makeFormatter()
    private let trailingClockFormatter = ClockField.makeFormatter()
    private var loadingSolarTermYears: Set<Int> = []

    @Published var theme: CalendarTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }
    @Published var popoverLayout: CalendarPopoverLayout {
        didSet { defaults.set(try? JSONEncoder().encode(popoverLayout), forKey: Key.popoverLayout) }
    }
    @Published var firstWeekday: Int {
        didSet { defaults.set(firstWeekday, forKey: Key.firstWeekday) }
    }
    @Published private(set) var clockFields: [ClockFieldOption] {
        didSet { defaults.set(try? JSONEncoder().encode(clockFields), forKey: Key.clockFields) }
    }
    @Published var customClockFormat: String {
        didSet { defaults.set(customClockFormat, forKey: Key.customClockFormat) }
    }
    @Published private(set) var holidaySelection: HolidaySelection {
        didSet { defaults.set(try? JSONEncoder().encode(holidaySelection), forKey: Key.holidaySources) }
    }

    @Published private var cachedHolidays: HolidayCalendar
    @Published private var refreshingDefaultYears: Set<Int> = []
    @Published private(set) var refreshingSourceIDs: Set<UUID> = []
    @Published private(set) var solarTerms: SolarTerms
    @Published private(set) var loginItemStatus = SMAppService.mainApp.status
    @Published private(set) var loginItemError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let appID = Bundle.main.bundleIdentifier ?? "local.calendar.app"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(appID, isDirectory: true)
        let cacheDirectory = support?.appendingPathComponent("HolidayCache", isDirectory: true)
        let solarDirectory = support?.appendingPathComponent("SolarTermCache", isDirectory: true)
        self.cacheDirectory = cacheDirectory
        solarTermCacheDirectory = solarDirectory
        cachedHolidays = cacheDirectory.map(HolidayCalendar.init(directory:)) ?? HolidayCalendar(documents: [])
        solarTerms = solarDirectory.map(SolarTerms.cached(in:)) ?? .bundled
        theme = defaults.string(forKey: Key.theme).flatMap(CalendarTheme.init(rawValue:)) ?? .amber
        popoverLayout = defaults.data(forKey: Key.popoverLayout)
            .flatMap { try? JSONDecoder().decode(CalendarPopoverLayout.self, from: $0) }?.clamped ?? CalendarPopoverLayout()
        let storedWeekday = defaults.integer(forKey: Key.firstWeekday)
        firstWeekday = (1...7).contains(storedWeekday) ? storedWeekday : 2
        clockFields = Self.loadClockFields(from: defaults)
        customClockFormat = defaults.string(forKey: Key.customClockFormat) ?? ""
        if let data = defaults.data(forKey: Key.holidaySources),
           let selection = try? JSONDecoder().decode(HolidaySelection.self, from: data) {
            holidaySelection = selection
        } else {
            let files = defaults.dictionary(forKey: Key.legacyHolidayFiles) as? [String: Data] ?? [:]
            let source = SavedHolidaySource(name: "本地导入", files: files)
            let activeID = defaults.string(forKey: Key.legacyHolidaySource) == "imported" ? source.id : nil
            let migrated = files.isEmpty ? HolidaySelection() : HolidaySelection(sources: [source], activeID: activeID)
            holidaySelection = migrated
            if !files.isEmpty {
                defaults.set(try? JSONEncoder().encode(migrated), forKey: Key.holidaySources)
            }
        }
    }

    var defaultHolidays: HolidayCalendar { HolidayCalendar.bundled.replacingYears(with: cachedHolidays) }
    var isRefreshingDefaultHolidays: Bool { !refreshingDefaultYears.isEmpty }

    var launchesAtLogin: Bool { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }

    func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        if loginItemStatus != status { loginItemStatus = status }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        refreshLoginItemStatus()
        loginItemError = nil
        guard launchesAtLogin != enabled else { return }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItemStatus()
    }

    var holidays: HolidayCalendar {
        let baseline = defaultHolidays
        var calendar = holidaySelection.activeSource.map { baseline.replacingYears(with: $0.calendar) } ?? baseline
        calendar.solarTerms = solarTerms
        return calendar
    }

    func clockItems(at date: Date) -> [ClockDisplayItem] {
        let custom = customClockFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled = clockFields.filter(\.isEnabled).map(\.field)

        func textItems(_ fields: ArraySlice<ClockField>, formatter: DateFormatter) -> [ClockDisplayItem] {
            guard !fields.isEmpty else { return [] }
            let pattern = fields.map { $0 == .custom && !custom.isEmpty ? String(custom.prefix(80)) : $0.pattern }
                .joined(separator: " ")
            return [.text(formatter.menuBarTitle(at: date, pattern: pattern))]
        }

        guard let icon = enabled.firstIndex(of: .icon) else {
            return textItems(enabled[...], formatter: leadingClockFormatter)
        }
        return textItems(enabled[..<icon], formatter: leadingClockFormatter) + [.icon]
            + textItems(enabled[(icon + 1)...], formatter: trailingClockFormatter)
    }

    private static func loadClockFields(from defaults: UserDefaults) -> [ClockFieldOption] {
        if let data = defaults.data(forKey: Key.clockFields),
           let saved = try? JSONDecoder().decode([ClockFieldOption].self, from: data) {
            var seen = Set<ClockField>()
            let unique = saved.filter { seen.insert($0.field).inserted }
            if unique.contains(where: \.isEnabled) {
                let icon = seen.insert(.icon).inserted ? [ClockFieldOption(field: .icon, isEnabled: true)] : []
                return icon + unique + ClockField.allCases.filter { !seen.contains($0) }.map { ClockFieldOption(field: $0, isEnabled: false) }
            }
        }
        let fields: [ClockField]
        switch defaults.string(forKey: Key.legacyClockFormat) ?? "" {
        case "compact": fields = [.numericDate, .time]
        case "dateOnly": fields = [.date, .weekday]
        case "timeOnly": fields = [.timeWithSeconds]
        case "custom" where !(defaults.string(forKey: Key.customClockFormat) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            fields = [.custom]
        default: fields = ClockField.defaultFields
        }
        let leadingFields: [ClockField] = [.icon, .year]
        let ordered = leadingFields + fields.filter { !leadingFields.contains($0) }
            + ClockField.allCases.filter { !leadingFields.contains($0) && !fields.contains($0) }
        return ordered.map { ClockFieldOption(field: $0, isEnabled: $0 == .icon || fields.contains($0)) }
    }

    func setClockField(_ field: ClockField, enabled: Bool) {
        guard let index = clockFields.firstIndex(where: { $0.field == field }),
              enabled || clockFields.contains(where: { $0.field != field && $0.isEnabled }) else { return }
        clockFields[index].isEnabled = enabled
    }

    @discardableResult
    func moveClockField(_ field: ClockField, to target: ClockField) -> Bool {
        guard let from = clockFields.firstIndex(where: { $0.field == field }),
              let to = clockFields.firstIndex(where: { $0.field == target }), from != to else { return false }
        var fields = clockFields
        let option = fields.remove(at: from)
        fields.insert(option, at: to)
        clockFields = fields
        return true
    }

    func importHolidays(from urls: [URL]) throws {
        guard let first = urls.first else { return }
        guard holidaySelection.canAddSource else { throw HolidaySourceError.sourceLimit }
        var files: [String: Data] = [:]
        for url in urls {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let calendar = try? JSONDecoder().decode(HolidayYear.self, from: data) else {
                throw HolidaySourceError.invalidFile(url.lastPathComponent)
            }
            let year = String(calendar.year)
            guard files[year] == nil else { throw HolidaySourceError.duplicateYear(calendar.year) }
            files[year] = data
        }
        let label = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "本地 JSON · \(urls.count) 个文件"
        saveSource(SavedHolidaySource(name: label, files: files))
    }

    func addRemoteHolidaySource(_ address: String) throws -> UUID {
        guard holidaySelection.canAddSource else { throw HolidaySourceError.sourceLimit }
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else { throw HolidaySourceError.invalidAddress }
        guard !holidaySelection.sources.contains(where: { $0.remoteURL == url }) else { throw HolidaySourceError.duplicateAddress }
        let source = SavedHolidaySource(name: host, remoteURL: url)
        saveSource(source)
        return source.id
    }

    func selectHolidaySource(_ id: UUID?) {
        guard id == nil || holidaySelection.sources.contains(where: { $0.id == id }) else { return }
        holidaySelection.activeID = id
    }

    func removeHolidaySource(_ id: UUID) {
        var selection = holidaySelection
        selection.sources.removeAll { $0.id == id }
        if selection.activeID == id { selection.activeID = nil }
        holidaySelection = selection
    }

    private func saveSource(_ source: SavedHolidaySource) {
        var selection = holidaySelection
        selection.sources.append(source)
        selection.activeID = source.id
        holidaySelection = selection
    }

    func refreshHolidaySource(_ id: UUID, now: Date = .now, force: Bool = true) async throws {
        guard let index = holidaySelection.sources.firstIndex(where: { $0.id == id }),
              let url = holidaySelection.sources[index].remoteURL, !refreshingSourceIDs.contains(id) else { return }
        let lastAttempt = holidaySelection.sources[index].lastAttempt
        guard force || Self.isRefreshDue(since: lastAttempt, now: now) else { return }

        refreshingSourceIDs.insert(id)
        defer { refreshingSourceIDs.remove(id) }
        holidaySelection.sources[index].lastAttempt = now
        let (data, year) = try await Self.downloadHolidayYear(from: url)

        // 用户可以在下载过程中删除来源，响应只更新仍然存在的同一项。
        guard let currentIndex = holidaySelection.sources.firstIndex(where: { $0.id == id }) else { return }
        holidaySelection.sources[currentIndex].files[String(year)] = data
    }

    func refreshHolidaysIfNeeded(now: Date = .now) async {
        let currentYear = CalendarDates.localGregorian.component(.year, from: now)
        async let solar: Void = loadSolarTerms(years: [currentYear, currentYear + 1], now: now)
        if let source = holidaySelection.activeSource, source.remoteURL != nil {
            try? await refreshHolidaySource(source.id, now: now, force: false)
        }
        _ = try? await refreshDefaultHolidays(now: now, force: false)
        await solar
    }

    func loadCalendarYears(_ years: Set<Int>, now: Date = .now) async {
        let currentYear = CalendarDates.localGregorian.component(.year, from: now)
        let covered = defaultHolidays.years
        let missingHistory = years.filter { $0 >= 2007 && $0 < currentYear && !covered.contains($0) }
        async let solar: Void = loadSolarTerms(years: years, now: now)
        _ = try? await refreshDefaultHolidays(now: now, force: false, years: missingHistory)
        await solar
    }

    private func loadSolarTerms(years: Set<Int>, now: Date) async {
        guard let solarTermCacheDirectory else { return }
        var attempts = defaults.dictionary(forKey: Key.solarTermRefreshAttempts) as? [String: Date] ?? [:]
        let due = years.filter { year in
            SolarTerms.supportedYears.contains(year) && !solarTerms.years.contains(year) && !loadingSolarTermYears.contains(year)
                && Self.isRefreshDue(since: attempts[String(year)], now: now)
        }
        guard !due.isEmpty else { return }

        loadingSolarTermYears.formUnion(due)
        defer { loadingSolarTermYears.subtract(due) }
        for year in due { attempts[String(year)] = now }
        defaults.set(attempts, forKey: Key.solarTermRefreshAttempts)

        for year in due.sorted() {
            let url = URL(string: "https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T\(year)c.txt")!
            do {
                let data = try await Self.downloadCalendarResource(from: url)
                guard let entries = SolarTerms.parseObservatoryTable(data, year: year) else { continue }
                try FileManager.default.createDirectory(at: solarTermCacheDirectory, withIntermediateDirectories: true)
                try data.write(to: solarTermCacheDirectory.appendingPathComponent("\(year).txt"), options: .atomic)
                solarTerms = solarTerms.adding(entries)
            } catch {
                continue
            }
        }
    }

    func refreshDefaultHolidays(now: Date = .now, force: Bool = true, years: Set<Int>? = nil) async throws -> Bool {
        guard let cacheDirectory else { throw HolidaySourceError.cacheUnavailable }
        let currentYear = CalendarDates.localGregorian.component(.year, from: now)
        var attempts = defaults.dictionary(forKey: Key.holidayRefreshAttempts) as? [String: Date] ?? [:]
        let activeYears = holidaySelection.activeSource?.calendar.years ?? []
        let dueYears = (years ?? [currentYear, currentYear + 1]).filter { year in
            !refreshingDefaultYears.contains(year)
                && (force || (!activeYears.contains(year) && Self.isRefreshDue(since: attempts[String(year)], now: now)))
        }
        guard !dueYears.isEmpty else { return false }

        refreshingDefaultYears.formUnion(dueYears)
        defer { refreshingDefaultYears.subtract(dueYears) }
        for year in dueYears { attempts[String(year)] = now }
        defaults.set(attempts, forKey: Key.holidayRefreshAttempts)

        var failures: [Int] = []
        for year in dueYears.sorted() {
            let url = URL(string: "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/\(year).json")!
            do {
                let (data, downloadedYear) = try await Self.downloadHolidayYear(from: url)
                guard year == downloadedYear else {
                    failures.append(year)
                    continue
                }
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                let file = cacheDirectory.appendingPathComponent("\(year).json")
                try data.write(to: file, options: .atomic)
            } catch {
                failures.append(year)
            }
        }
        if failures.count < dueYears.count { cachedHolidays = HolidayCalendar(directory: cacheDirectory) }
        if !failures.isEmpty { throw HolidaySourceError.defaultUpdateFailed(failures) }
        return true
    }

    private static func isRefreshDue(since lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        let age = now.timeIntervalSince(lastAttempt)
        return age < 0 || age >= 7 * 24 * 60 * 60
    }

    private static func downloadHolidayYear(from url: URL) async throws -> (Data, Int) {
        let data = try await downloadCalendarResource(from: url)
        guard let year = try? JSONDecoder().decode(HolidayYear.self, from: data) else {
            throw HolidaySourceError.invalidFile(url.lastPathComponent.isEmpty ? "远程文件" : url.lastPathComponent)
        }
        return (data, year.year)
    }

    private static func downloadCalendarResource(from url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard response.statusCode == 200 else { throw HolidaySourceError.httpStatus(response.statusCode) }
        return data
    }
}

struct CalendarPopoverLayout: Codable, Equatable {
    enum Side: String, Codable {
        case left, right
    }

    static let minimumCalendarWidth = 320
    static let minimumDetailsWidth = 116
    static let minimumHeight = 340
    static let outerPadding: CGFloat = 14
    static let dividerWidth: CGFloat = 16

    var calendarWidth = 396
    var detailsWidth = 164
    var height = 382
    var detailsSide: Side = .right
    var allowsDragResize = true

    var size: CGSize {
        CGSize(width: CGFloat(calendarWidth) + CGFloat(detailsWidth) + 2 * Self.outerPadding + Self.dividerWidth,
               height: CGFloat(height))
    }

    var clamped: Self {
        var value = self
        value.calendarWidth = max(calendarWidth, Self.minimumCalendarWidth)
        value.detailsWidth = max(detailsWidth, Self.minimumDetailsWidth)
        value.height = max(height, Self.minimumHeight)
        return value
    }

    func fitted(in space: CGSize?) -> Self {
        var value = clamped
        guard let space else { return value }
        let available = Self.availableColumnWidth(in: space)
        value.detailsWidth = min(value.detailsWidth, available - Self.minimumCalendarWidth)
        value.calendarWidth = min(value.calendarWidth, available - value.detailsWidth)
        value.height = min(value.height, max(Self.minimumHeight, Int(space.height)))
        return value
    }

    func resizingColumn(on side: Side, widthChange: Int, heightChange: Int, in space: CGSize?) -> Self {
        var value = self
        let available = space.map(Self.availableColumnWidth(in:))
        if side == detailsSide {
            let limit = available.map { $0 - calendarWidth } ?? Int.max
            value.detailsWidth = max(Self.minimumDetailsWidth, min(detailsWidth + widthChange, limit))
        } else {
            let limit = available.map { $0 - detailsWidth } ?? Int.max
            value.calendarWidth = max(Self.minimumCalendarWidth, min(calendarWidth + widthChange, limit))
        }
        value.height = max(Self.minimumHeight, min(height + heightChange, space.map { Int($0.height) } ?? Int.max))
        return value
    }

    private static func availableColumnWidth(in space: CGSize) -> Int {
        max(minimumCalendarWidth + minimumDetailsWidth, Int(space.width - 2 * outerPadding - dividerWidth))
    }
}

struct HolidaySelection: Codable {
    static let maximumSources = 3
    var sources: [SavedHolidaySource] = []
    var activeID: UUID? = nil

    var activeSource: SavedHolidaySource? { sources.first { $0.id == activeID } }
    var canAddSource: Bool { sources.count < Self.maximumSources }
}

struct SavedHolidaySource: Codable, Identifiable {
    var id = UUID()
    let name: String
    var remoteURL: URL? = nil
    var files: [String: Data] = [:]
    var lastAttempt: Date? = nil

    var calendar: HolidayCalendar {
        let documents = files.values.compactMap { try? JSONDecoder().decode(HolidayYear.self, from: $0) }
            .sorted { $0.year < $1.year }
        return HolidayCalendar(documents: documents)
    }
}

private enum HolidaySourceError: LocalizedError {
    case sourceLimit, invalidAddress, duplicateAddress, invalidFile(String), duplicateYear(Int), httpStatus(Int)
    case cacheUnavailable, defaultUpdateFailed([Int])

    var errorDescription: String? {
        switch self {
        case .sourceLimit: return "最多保存三个自定义假期来源。"
        case .invalidAddress: return "请输入直接返回年度 JSON 的 HTTPS 地址。"
        case .duplicateAddress: return "已保存这个远程地址。"
        case .invalidFile(let file): return "无法读取 \(file)，请使用 holiday-cn 格式的年度 JSON。"
        case .duplicateYear(let year): return "同一来源只能导入一份 \(year) 年的数据。"
        case .httpStatus(let status): return "下载失败，服务器返回 HTTP \(status)。"
        case .cacheUnavailable: return "无法访问本地假期缓存目录。"
        case .defaultUpdateFailed(let years):
            return "holiday-cn 的 \(years.map(String.init).joined(separator: "、")) 年数据未更新，继续使用本地数据。"
        }
    }
}

extension DateFormatter {
    func menuBarTitle(at date: Date, pattern: String) -> String {
        let timeZone = TimeZone.current
        if self.timeZone != timeZone { self.timeZone = timeZone }
        if dateFormat != pattern { dateFormat = pattern }
        let text = string(from: date).components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            dateFormat = ClockField.defaultFields.filter { $0 != .icon }.map(\.pattern).joined(separator: " ")
            return string(from: date)
        }
        return text
    }
}

enum ClockDisplayItem: Equatable {
    case icon
    case text(String)
}

struct ClockFieldOption: Codable, Identifiable {
    let field: ClockField
    var isEnabled: Bool
    var id: ClockField { field }
}

enum ClockField: String, CaseIterable, Codable {
    case icon, year, date, numericDate, weekday, time, timeWithSeconds, custom

    static let defaultFields: [ClockField] = [.icon, .year, .date, .weekday, .timeWithSeconds]

    var label: String {
        switch self {
        case .icon: return "日历图标"
        case .date: return "月日"
        case .numericDate: return "数字日期"
        case .weekday: return "星期"
        case .time: return "时间（时:分）"
        case .timeWithSeconds: return "时间（时:分:秒）"
        case .year: return "年份"
        case .custom: return "自定义"
        }
    }

    var pattern: String {
        switch self {
        case .icon: return ""
        case .date: return "M月d日"
        case .numericDate: return "yyyy-MM-dd"
        case .weekday: return "EEE"
        case .time: return "HH:mm"
        case .timeWithSeconds: return "HH:mm:ss"
        case .year: return "yyyy年"
        case .custom: return "yyyy-MM-dd HH:mm"
        }
    }

    static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter
    }
}

enum CalendarTheme: String, CaseIterable, Identifiable {
    case amber, blue, green, lilac, rose

    var id: Self { self }

    var label: String {
        switch self {
        case .amber: return "暖黄"
        case .blue: return "晴蓝"
        case .green: return "松绿"
        case .lilac: return "淡紫"
        case .rose: return "珊瑚"
        }
    }

    var fill: Color {
        switch self {
        case .amber: return Color(hex: 0xF4BB37)
        case .blue: return Color(hex: 0x94C8F6)
        case .green: return Color(hex: 0x9CD2AD)
        case .lilac: return Color(hex: 0xCDC0F2)
        case .rose: return Color(hex: 0xF3AAA2)
        }
    }

    var outline: Color {
        switch self {
        case .amber: return Color(hex: 0x956208)
        case .blue: return Color(hex: 0x27679C)
        case .green: return Color(hex: 0x367447)
        case .lilac: return Color(hex: 0x7255A3)
        case .rose: return Color(hex: 0xA44C43)
        }
    }
}
