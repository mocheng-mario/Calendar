import SwiftUI

struct CalendarCountdownView: View {
    let holiday: CalendarOccasion?
    let solarTerm: CalendarOccasion?
    let today: Date
    let schedules: [CalendarSchedule]
    let palette: CalendarPalette
    let showsDates: Bool
    let addSchedule: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("倒计时")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 2)
                Button(action: addSchedule) {
                    if showsDates {
                        Label("添加日程", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.selection)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.selection)
                            .frame(width: 20, height: 22)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加日程")
                .help("添加日程")
            }
            .frame(height: 22)
            .padding(.bottom, 4)

            dateRow("法定节假日", occasion: holiday, color: palette.weekend)
            separator
            dateRow("二十四节气", occasion: solarTerm, color: palette.solarTerm)
            separator

            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let schedule = schedules.first(where: { $0.date > context.date }) {
                    countdownRow(title: schedule.displayTitle, category: "日程", date: scheduleLabel(schedule.date),
                                 remaining: timeRemaining(until: schedule.date, from: context.date),
                                 color: palette.selection)
                } else {
                    countdownRow(title: "暂无近期日程", category: "日程", date: nil, remaining: nil, color: palette.selection)
                }
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(palette.divider.opacity(0.7))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func dateRow(_ label: String, occasion: CalendarOccasion?, color: Color) -> some View {
        let calendar = CalendarDates.gregorian
        let dateLabel = occasion.map { event in
            let year = calendar.component(.year, from: event.date)
            let month = calendar.component(.month, from: event.date)
            let day = calendar.component(.day, from: event.date)
            let monthDay = "\(month)月\(day)日"
            return year == calendar.component(.year, from: today) ? monthDay : "\(year)年\(monthDay)"
        }
        let days = occasion.flatMap { calendar.dateComponents([.day], from: today, to: $0.date).day }
        let remaining = days.map { $0 == 0 ? "今天" : "\($0) 天" }
        return countdownRow(title: occasion?.name ?? "暂无已收录日期", category: label, date: dateLabel, remaining: remaining, color: color)
    }

    private func countdownRow(title: String, category: String, date: String?, remaining: String?, color: Color) -> some View {
        let subtitle = date.map { "\(category) · \($0)" } ?? category
        let name = Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(remaining == nil ? palette.secondary : palette.primary)
            .lineLimit(1)
        let dot = Circle().fill(color).frame(width: 5, height: 5).accessibilityHidden(true)

        return VStack(alignment: .leading, spacing: 2) {
            if showsDates {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    name
                    Spacer(minLength: 0)
                    if let remaining { countdownValue(remaining) }
                }
                HStack(spacing: 5) {
                    dot
                    ViewThatFits(in: .horizontal) {
                        Text(subtitle).fixedSize(horizontal: true, vertical: false)
                        Text(category).lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                }
            } else {
                HStack(spacing: 5) {
                    dot
                    name
                }
                if let remaining {
                    countdownValue(remaining)
                } else {
                    Text(category)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(title) · \(subtitle)")
        .frame(height: 44)
        .accessibilityElement(children: .combine)
    }

    private func countdownValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(palette.primary)
            .fixedSize()
    }

    private func scheduleLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN")))
    }

    private func timeRemaining(until date: Date, from now: Date) -> String {
        let seconds = Int(ceil(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let clock = String(format: "%02d:%02d:%02d", seconds / 3600 % 24, seconds / 60 % 60, seconds % 60)
        return days == 0 ? clock : "\(days) 天 \(clock)"
    }
}
