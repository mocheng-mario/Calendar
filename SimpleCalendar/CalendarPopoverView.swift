import SwiftUI

struct CalendarPopoverView: View {
    static let contentSize = CGSize(width: 604, height: 341)

    @ObservedObject var model: CalendarModel
    @ObservedObject var settings: CalendarSettings
    let openSettings: () -> Void
    let openSchedule: (Date) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private static let gridSpacing: CGFloat = 3
    private let columns = Array(repeating: GridItem(.flexible(), spacing: CalendarPopoverView.gridSpacing), count: 7)
    private var weekdays: [String] {
        (0..<7).map { CalendarDay.weekdayNames[(settings.firstWeekday - 1 + $0) % 7] }
    }
    private var palette: CalendarPalette { CalendarPalette(isDark: colorScheme == .dark, theme: settings.theme) }

    var body: some View {
        let days = model.days(startingOn: settings.firstWeekday)
        let holidays = settings.holidays
        let years = Set(days.map { CalendarDates.gregorian.component(.year, from: $0.date) })
        let scheduleDays = Dictionary(grouping: model.schedules) { CalendarDates.localDay(at: $0.date) }
        let selectedSchedules = scheduleDays[model.selectedDate] ?? []
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                if let day = days.first(where: { $0.date == model.selectedDate }) {
                    dateDetail(for: day, holidays: holidays)
                    Divider()
                }

                CalendarCountdownView(holiday: holidays.nextStatutoryDay(from: model.today),
                                      solarTerm: holidays.solarTerms.next(from: model.today), today: model.today,
                                      schedules: model.schedules, palette: palette) {
                    openSchedule(model.selectedDate)
                }

                if !selectedSchedules.isEmpty {
                    Divider()
                    daySchedules(selectedSchedules)
                }
            }
            .frame(width: 204, alignment: .leading)

            calendarGrid(days, holidays: holidays, scheduleDays: Set(scheduleDays.keys))
                .frame(width: 354)
        }
        .padding(14)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .background(palette.background)
        .onAppear { loadYears(years) }
        .onChange(of: years) { loadYears($0) }
    }

    private func loadYears(_ years: Set<Int>) {
        Task { await settings.loadCalendarYears(years) }
    }

    private func calendarGrid(_ days: [CalendarDay], holidays: HolidayCalendar, scheduleDays: Set<Date>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            monthHeader
                .frame(height: 42)
                .padding(.bottom, 6)

            weekdayHeader
                .frame(height: 17)
                .padding(.bottom, 5)

            LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                ForEach(days) { day in
                    let solarTerm = holidays.solarTerms.name(on: day.date)
                    CalendarDayCell(day: day, isToday: day.date == model.today,
                                    isSelected: day.date == model.selectedDate, holiday: holidays[day.date],
                                    statutoryName: holidays.statutoryOccasion(on: day.date)?.name,
                                    festival: day.festival(solarTerm: solarTerm), solarTerm: solarTerm,
                                    hasSchedule: scheduleDays.contains(day.date),
                                    palette: palette) {
                        model.select(day.date)
                    }
                    .contextMenu {
                        Button {
                            openSchedule(day.date)
                        } label: {
                            Label("添加日程…", systemImage: "calendar.badge.plus")
                        }
                    }
                }
            }
            .frame(height: 6 * CalendarDayCell.height + 5 * Self.gridSpacing)
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 5) {
            Text(model.monthTitle)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            monthArrow("chevron.left", label: "上个月", offset: -1)

            Button(action: model.goToToday) {
                Text("今天")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(palette.cell, in: Capsule())
                    .overlay { Capsule().strokeBorder(palette.divider, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回今天")
            .help("返回今天")

            monthArrow("chevron.right", label: "下个月", offset: 1)

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
            .help("设置")
        }
    }

    private func monthArrow(_ symbol: String, label: String, offset: Int) -> some View {
        Button {
            model.moveMonth(by: offset)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .help(label)
    }

    private var weekdayHeader: some View {
        HStack(spacing: Self.gridSpacing) {
            ForEach(weekdays, id: \.self) { weekday in
                Text(weekday)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(weekday == "六" || weekday == "日" ? palette.weekend : palette.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func dateDetail(for day: CalendarDay, holidays: HolidayCalendar) -> some View {
        let solarTerm = holidays.solarTerms.name(on: day.date)
        let holiday = holidays[day.date]
        let festival = day.festival(solarTerm: solarTerm)
        let year = CalendarDates.gregorian.component(.year, from: day.date)
        let missing = [holidays.covers(day.date) ? nil : "调休未收录",
                       holidays.solarTerms.years.contains(year) ? nil : "节气未收录"].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text("\(day.day)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.primary)
                    .frame(width: 51, height: 48)
                    .background(palette.cell, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(day.month)月 · 星期\(day.weekdayName)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .accessibilityLabel("\(day.month)月\(day.day)日，星期\(day.weekdayName)")
                    Text(lunarDescription(day.lunarDate))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                }
            }

            if holiday != nil || festival != nil || solarTerm != nil {
                HStack(spacing: 5) {
                    if let holiday {
                        let status = holiday.isOffDay ? "休" : "班"
                        detailBadge("\(holiday.name) · \(status)", symbol: holiday.isOffDay ? "flag.fill" : "briefcase", color: palette.holiday(holiday))
                    }
                    if let festival, festival.name != holiday?.name {
                        detailBadge(festival.name, symbol: festival.symbol, color: palette.festival(festival))
                    }
                    if let solarTerm {
                        detailBadge(solarTerm, symbol: "leaf", color: palette.solarTerm)
                    }
                }
            }

            if !missing.isEmpty {
                Text(missing.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func daySchedules(_ schedules: [CalendarSchedule]) -> some View {
        let rowHeight: CGFloat = 20
        return VStack(alignment: .leading, spacing: 4) {
            Text("当天日程")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.primary)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(schedules) { schedule in
                        HStack(spacing: 8) {
                            Text(schedule.date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN"))))
                                .foregroundStyle(palette.secondary)
                                .monospacedDigit()
                                .fixedSize()
                            Text(schedule.displayTitle)
                                .lineLimit(1)
                                .help(schedule.displayTitle)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(palette.primary)
                        .frame(height: rowHeight)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxHeight: CGFloat(min(schedules.count, 3)) * rowHeight)
        }
    }

    private func lunarDescription(_ lunar: LunarDate?) -> String {
        guard let lunar else { return "农历日期不可用" }
        let description = "农历\(lunar.monthName)\(lunar.dayName)"
        return lunar.zodiac.map { "\(description) · \($0)年" } ?? description
    }

    private func detailBadge(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct CalendarDayCell: View {
    static let height: CGFloat = 38

    let day: CalendarDay
    let isToday: Bool
    let isSelected: Bool
    let holiday: HolidayDay?
    let statutoryName: String?
    let festival: Festival?
    let solarTerm: String?
    let hasSchedule: Bool
    let palette: CalendarPalette
    let action: () -> Void

    @State private var isHovered = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 7) }
    private var festivalColor: Color? { festival.map(palette.festival) }
    private var occasionName: String? { statutoryName ?? festival?.name ?? solarTerm }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(.system(size: 18, weight: isToday ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(dayColor)
                Text(occasionName ?? day.lunarDate?.gridLabel ?? "—")
                    .font(.system(size: 10, weight: occasionName == nil ? .regular : .medium))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background {
                ZStack {
                    shape.fill(isToday ? palette.today : palette.cell.opacity(day.isCurrentMonth ? 1 : 0.43))
                    if !isToday, day.isCurrentMonth, let festivalColor {
                        shape.fill(festivalColor.opacity(palette.isDark ? 0.16 : 0.07))
                    }
                }
            }
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if let holiday {
                    Text(holiday.isOffDay ? "休" : "班")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(isToday ? palette.todayText : palette.holiday(holiday))
                        .padding(3)
                }
            }
            .overlay(alignment: .topLeading) {
                if hasSchedule {
                    Circle().fill(isToday ? palette.todayText : palette.selection)
                        .frame(width: 4, height: 4)
                        .padding(4)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(accessibilityDescription))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayColor: Color {
        if isToday { return palette.todayText }
        if !day.isCurrentMonth { return palette.muted }
        if let holiday { return holiday.isOffDay ? palette.holiday(holiday) : palette.primary }
        return day.isWeekend ? palette.weekend : palette.primary
    }

    private var subtitleColor: Color {
        if isToday { return palette.todaySubtitle }
        if !day.isCurrentMonth { return palette.muted }
        if let festivalColor { return festivalColor }
        if statutoryName != nil, let holiday { return palette.holiday(holiday) }
        return solarTerm == nil ? palette.secondary : palette.solarTerm
    }

    private var borderColor: Color {
        if isSelected { return isToday ? palette.todayText.opacity(0.55) : palette.selection }
        return isHovered ? palette.secondary.opacity(0.55) : .clear
    }

    private var accessibilityDescription: String {
        var description = "\(day.month)月\(day.day)日，星期\(day.weekdayName)"
        if isToday { description += "，今天" }
        if let lunarDate = day.lunarDate { description += "，农历\(lunarDate.monthName)\(lunarDate.dayName)" }
        if let festival { description += "，\(festival.name)" }
        if let solarTerm { description += "，\(solarTerm)" }
        if let holiday { description += holiday.isOffDay ? "，\(holiday.name)放假" : "，\(holiday.name)调休上班" }
        if hasSchedule { description += "，有日程" }
        return description
    }
}

struct CalendarPalette {
    let isDark: Bool
    let theme: CalendarTheme

    var background: Color { color(0xF5F6F8, 0x23252A) }
    var cell: Color { color(0xFFFFFF, 0x30333A) }
    var divider: Color { color(0xDCDFE4, 0x41444C) }
    var primary: Color { color(0x303640, 0xF2F3F6) }
    var secondary: Color { color(0x616976, 0xB9C0CA) }
    var muted: Color { color(0x707884, 0x9DA5B3) }
    var weekend: Color { color(0xB73E38, 0xFF918B) }
    var selection: Color { isDark ? theme.fill : theme.outline }
    var today: Color { theme.fill }
    var todayText: Color { Color(hex: 0x24242A) }
    var todaySubtitle: Color { Color(hex: 0x47404A) }
    var solarTerm: Color { color(0x287153, 0x8AD0AA) }

    func holiday(_ holiday: HolidayDay) -> Color {
        holiday.isOffDay ? weekend : color(0x286799, 0x9ABFF0)
    }

    func festival(_ festival: Festival) -> Color {
        switch festival {
        case .springFestival, .springFestivalEve, .lanternFestival: return color(0xAD3733, 0xFF9B93)
        case .dragonBoatFestival, .qingming: return color(0x276C51, 0x82CBA9)
        case .midAutumnFestival: return color(0x8C5A19, 0xEBC47A)
        }
    }

    private func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(hex: isDark ? dark : light)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
