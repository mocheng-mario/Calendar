import AppKit
import SwiftUI

struct CalendarPopoverView: View {
    private enum ResizeHandle {
        case divider
        case corner(CalendarPopoverLayout.Side)
    }
    private struct ResizeStart {
        let pointer: CGPoint
        let layout: CalendarPopoverLayout
    }

    @ObservedObject var model: CalendarModel
    @ObservedObject var settings: CalendarSettings
    let availableSize: CGSize?
    let openSettings: () -> Void
    let openSchedule: (Date) -> Void
    let resize: (CGSize) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var resizeStart: ResizeStart?
    @State private var resizePreview: CalendarPopoverLayout?
    @State private var isYearPickerOpen = false

    private static let gridSpacing: CGFloat = 3
    private static let monthHeaderHeight: CGFloat = 40
    private static let monthHeaderInset: CGFloat = 12
    private let columns = Array(repeating: GridItem(.flexible(), spacing: CalendarPopoverView.gridSpacing), count: 7)
    private var weekdays: [String] {
        (0..<7).map { CalendarDay.weekdayNames[(settings.firstWeekday - 1 + $0) % 7] }
    }
    private var palette: CalendarPalette { CalendarPalette(isDark: colorScheme == .dark, theme: settings.theme) }

    init(model: CalendarModel, settings: CalendarSettings, availableSize: CGSize?,
         openSettings: @escaping () -> Void, openSchedule: @escaping (Date) -> Void,
         resize: @escaping (CGSize) -> Void) {
        self.model = model
        self.settings = settings
        self.availableSize = availableSize
        self.openSettings = openSettings
        self.openSchedule = openSchedule
        self.resize = resize
    }

    var body: some View {
        let layout = resizePreview ?? settings.popoverLayout.fitted(in: availableSize)
        let days = model.days(startingOn: settings.firstWeekday)
        let holidays = settings.holidays
        let years = Set(days.map { CalendarDates.gregorian.component(.year, from: $0.date) })
        let scheduleDays = Dictionary(grouping: model.schedules) { CalendarDates.localDay(at: $0.date) }
        let selectedSchedules = scheduleDays[model.selectedDate] ?? []
        let details = detailsPane(day: days.first { $0.date == model.selectedDate }, holidays: holidays,
                                  schedules: selectedSchedules, width: layout.detailsWidth)
        let calendar = calendarGrid(days, holidays: holidays, scheduleDays: Set(scheduleDays.keys))
            .frame(width: CGFloat(layout.calendarWidth))
        HStack(alignment: .top, spacing: 0) {
            if layout.detailsSide == .left {
                details
                paneDivider(enabled: layout.allowsDragResize)
                calendar
            } else {
                calendar
                paneDivider(enabled: layout.allowsDragResize)
                details
            }
        }
        .padding(CalendarPopoverLayout.outerPadding)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
        .background(palette.background)
        .overlay(alignment: .bottomLeading) {
            if layout.allowsDragResize { cornerHandle(.left, detailsSide: layout.detailsSide) }
        }
        .overlay(alignment: .bottomTrailing) {
            if layout.allowsDragResize { cornerHandle(.right, detailsSide: layout.detailsSide) }
        }
        .overlay(alignment: .topLeading) {
            if isYearPickerOpen {
                let calendarLeading = layout.detailsSide == .left
                    ? CGFloat(layout.detailsWidth) + CalendarPopoverLayout.dividerWidth : 0
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { isYearPickerOpen = false }
                        .accessibilityHidden(true)
                    yearDropdown
                        .padding(.leading, CalendarPopoverLayout.outerPadding + calendarLeading + Self.monthHeaderInset)
                        .padding(.top, CalendarPopoverLayout.outerPadding + Self.monthHeaderHeight - 4)
                }
            }
        }
        .onAppear { loadYears(years) }
        .onChange(of: years) { loadYears($0) }
    }

    private func cornerHandle(_ side: CalendarPopoverLayout.Side, detailsSide: CalendarPopoverLayout.Side) -> some View {
        let pane = side == detailsSide ? "详情栏" : "月历"
        let label = "拖动调整\(pane)宽度和弹窗高度"
        return Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(palette.secondary)
            .scaleEffect(x: side == .left ? -1 : 1, y: 1)
            .frame(width: 24, height: 16)
            .contentShape(Rectangle())
            .gesture(resizeGesture(.corner(side)))
            .accessibilityLabel(Text(label))
            .help(label)
            .padding(2)
    }

    private func detailsPane(day: CalendarDay?, holidays: HolidayCalendar, schedules: [CalendarSchedule], width: Int) -> some View {
        let compact = width < 158
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let day {
                    dateDetail(for: day, holidays: holidays, compact: compact)
                    Divider()
                }

                CalendarCountdownView(holiday: holidays.nextStatutoryDay(from: model.today),
                                      solarTerm: holidays.solarTerms.next(from: model.today), today: model.today,
                                      schedules: model.schedules, palette: palette, showsDates: !compact) {
                    openSchedule(model.selectedDate)
                }

                if !schedules.isEmpty {
                    Divider()
                    daySchedules(schedules)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: CGFloat(width))
    }

    @ViewBuilder
    private func paneDivider(enabled: Bool) -> some View {
        let area = Color.clear.frame(width: CalendarPopoverLayout.dividerWidth).frame(maxHeight: .infinity)
        if enabled {
            area.overlay {
                Capsule().fill(palette.muted.opacity(0.45)).frame(width: 2, height: 24)
            }
            .contentShape(Rectangle())
            .gesture(resizeGesture(.divider))
            .accessibilityLabel("拖动调整两栏比例")
            .help("拖动调整两栏比例")
        } else {
            area.allowsHitTesting(false)
        }
    }

    private func resizeGesture(_ handle: ResizeHandle) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                // NSPopover 会随尺寸重新锚定，使用屏幕坐标以免窗口移动干扰位移。
                let pointer = NSEvent.mouseLocation
                let origin = resizeStart ?? ResizeStart(
                    pointer: CGPoint(x: pointer.x - value.translation.width, y: pointer.y + value.translation.height),
                    layout: settings.popoverLayout.fitted(in: availableSize)
                )
                if resizeStart == nil { resizeStart = origin }
                let horizontal = Int((pointer.x - origin.pointer.x).rounded())
                var next = origin.layout
                switch handle {
                case .divider:
                    let adjustment = origin.layout.detailsSide == .left ? horizontal : -horizontal
                    let delta = min(max(adjustment, CalendarPopoverLayout.minimumDetailsWidth - next.detailsWidth),
                                    next.calendarWidth - CalendarPopoverLayout.minimumCalendarWidth)
                    next.detailsWidth += delta
                    next.calendarWidth -= delta
                case .corner(let side):
                    next = origin.layout.resizingColumn(
                        on: side, widthChange: side == .left ? -horizontal : horizontal,
                        heightChange: Int((origin.pointer.y - pointer.y).rounded()), in: availableSize
                    )
                }
                let previous = resizePreview ?? origin.layout
                guard next != previous else { return }
                resizePreview = next
                if next.size != previous.size { resize(next.size) }
            }
            .onEnded { _ in
                if let resizePreview, resizePreview != resizeStart?.layout { settings.popoverLayout = resizePreview }
                resizePreview = nil
                resizeStart = nil
            }
    }

    private func loadYears(_ years: Set<Int>) {
        Task { await settings.loadCalendarYears(years) }
    }

    private func calendarGrid(_ days: [CalendarDay], holidays: HolidayCalendar, scheduleDays: Set<Date>) -> some View {
        let panelShape = RoundedRectangle(cornerRadius: 11)
        return VStack(alignment: .leading, spacing: 0) {
            monthHeader
                .padding(.horizontal, Self.monthHeaderInset)
                .frame(height: Self.monthHeaderHeight)
                .background(palette.toolbar)

            weekdayHeader
                .padding(.horizontal, 8)
                .frame(height: 20)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)
                .padding(.horizontal, 9)

            GeometryReader { geometry in
                let rowHeight = max(1, (geometry.size.height - 5 * Self.gridSpacing) / 6)
                LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                    ForEach(days) { day in
                        let solarTerm = holidays.solarTerms.name(on: day.date)
                        CalendarDayCell(day: day, isToday: day.date == model.today,
                                        isSelected: day.date == model.selectedDate, holiday: holidays[day.date],
                                        statutoryName: holidays.statutoryOccasion(on: day.date)?.name,
                                        festival: day.festival(solarTerm: solarTerm), solarTerm: solarTerm,
                                        hasSchedule: scheduleDays.contains(day.date),
                                        height: rowHeight, palette: palette) {
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
            }
            .padding(.horizontal, 8)
            .padding(.top, 3)
            .padding(.bottom, 6)
        }
        .background(palette.surface)
        .clipShape(panelShape)
        .overlay { panelShape.strokeBorder(palette.divider.opacity(0.65)).allowsHitTesting(false) }
    }

    private var monthHeader: some View {
        HStack(spacing: 5) {
            yearPicker

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                monthArrow("chevron.left", label: "上个月", offset: -1)
                Text(model.monthDayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.primary)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                monthArrow("chevron.right", label: "下个月", offset: 1)
            }

            Spacer(minLength: 4)

            Button(action: model.goToToday) {
                Text("回今天")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .frame(height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("返回今天")
            .help("返回今天")

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

    private var yearPicker: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return Button {
            isYearPickerOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Text("\(String(model.selectedYear))年")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(palette.surface.opacity(0.75), in: shape)
            .overlay { shape.strokeBorder(palette.divider) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("选择年份")
        .accessibilityValue(Text(String(model.selectedYear)))
        .help("选择年份")
    }

    private var yearDropdown: some View {
        let supported = SolarTerms.supportedYears
        let selectedYear = model.selectedYear
        let years = min(supported.lowerBound, selectedYear)...max(supported.upperBound, selectedYear)
        let rowHeight: CGFloat = 25
        let shape = RoundedRectangle(cornerRadius: 8)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(years.reversed()), id: \.self) { year in
                        let isSelected = year == selectedYear
                        Button {
                            isYearPickerOpen = false
                            guard !isSelected else { return }
                            model.goToYear(year)
                            Task { _ = try? await settings.refreshDefaultHolidays(force: false, years: [year]) }
                        } label: {
                            HStack {
                                Text("\(String(year))年").monospacedDigit()
                                Spacer(minLength: 8)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .accessibilityHidden(true)
                                }
                            }
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(palette.primary)
                            .padding(.horizontal, 8)
                            .frame(height: rowHeight)
                            .background(isSelected ? palette.toolbar : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(year)
                    }
                }
            }
            .frame(width: 104, height: 7 * rowHeight)
            .onAppear { proxy.scrollTo(selectedYear, anchor: .center) }
        }
        .padding(4)
        .background(palette.surface, in: shape)
        .overlay { shape.strokeBorder(palette.divider) }
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }

    private func monthArrow(_ symbol: String, label: String, offset: Int) -> some View {
        Button {
            model.moveMonth(by: offset)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .frame(width: 11, height: 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(Text(label))
        .help(label)
    }

    private var weekdayHeader: some View {
        HStack(spacing: Self.gridSpacing) {
            ForEach(weekdays, id: \.self) { weekday in
                Text("周\(weekday)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(weekday == "六" || weekday == "日" ? palette.weekend : palette.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func dateDetail(for day: CalendarDay, holidays: HolidayCalendar, compact: Bool) -> some View {
        let solarTerm = holidays.solarTerms.name(on: day.date)
        let holiday = holidays[day.date]
        let festival = day.festival(solarTerm: solarTerm)
        let isToday = day.date == model.today
        let year = CalendarDates.gregorian.component(.year, from: day.date)
        let missing = [holidays.covers(day.date) ? nil : "调休未收录",
                       holidays.solarTerms.years.contains(year) ? nil : "节气未收录"].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 5) {
            if compact {
                Text("\(day.month)月\(day.day)日 · 周\(day.weekdayName)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text(lunarDescription(day.lunarDate))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                HStack(spacing: 8) {
                    Text("\(day.day)")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? palette.todayText : palette.primary)
                        .frame(width: 42, height: 44)
                        .background(isToday ? palette.today : palette.surface, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(day.month)月 · 星期\(day.weekdayName)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .accessibilityLabel("\(day.month)月\(day.day)日，星期\(day.weekdayName)")
                        Text(lunarDescription(day.lunarDate))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                    }
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
        VStack(alignment: .leading, spacing: 4) {
            Text("当天日程")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.primary)
                .accessibilityAddTraits(.isHeader)

            LazyVStack(spacing: 0) {
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
                    .frame(height: 20)
                    .accessibilityElement(children: .combine)
                }
            }
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
    let day: CalendarDay
    let isToday: Bool
    let isSelected: Bool
    let holiday: HolidayDay?
    let statutoryName: String?
    let festival: Festival?
    let solarTerm: String?
    let hasSchedule: Bool
    let height: CGFloat
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
                    .font(.system(size: 18, weight: isToday || isSelected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(dayColor)
                Text(occasionName ?? day.lunarDate?.gridLabel ?? "—")
                    .font(.system(size: 11, weight: occasionName == nil ? .regular : .medium))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(highlight, in: shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(isToday ? palette.todayText.opacity(0.4) : palette.selection, lineWidth: 1)
                        .allowsHitTesting(false)
                }
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

    private var highlight: Color {
        if isToday { return palette.today }
        if isSelected { return palette.selection.opacity(palette.isDark ? 0.16 : 0.09) }
        if isHovered { return palette.primary.opacity(0.06) }
        guard day.isCurrentMonth else { return .clear }
        if let festivalColor { return festivalColor.opacity(palette.isDark ? 0.16 : 0.075) }
        if statutoryName != nil, let holiday { return palette.holiday(holiday).opacity(palette.isDark ? 0.14 : 0.065) }
        return solarTerm == nil ? .clear : palette.solarTerm.opacity(palette.isDark ? 0.11 : 0.045)
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

    var background: Color { color(0xF4F5F6, 0x23252A) }
    var surface: Color { color(0xFFFFFF, 0x2B2D32) }
    var toolbar: Color { theme.fill.opacity(isDark ? 0.10 : 0.13) }
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
