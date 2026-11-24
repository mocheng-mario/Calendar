import SwiftUI

struct CalendarCountdownView: View {
    let holiday: CalendarOccasion?
    let solarTerm: CalendarOccasion?
    let today: Date
    let schedules: [CalendarSchedule]
    let palette: CalendarPalette
    let addSchedule: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("倒计时")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: addSchedule) {
                    Label("添加日程", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.selection)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 22)

            dateRow("法定节假日", occasion: holiday, color: palette.weekend)
            dateRow("二十四节气", occasion: solarTerm, color: palette.solarTerm)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let schedule = schedules.first(where: { $0.date > context.date }) {
                    countdownRow(title: schedule.displayTitle, subtitle: "日程 · \(scheduleLabel(schedule.date))",
                                 remaining: timeRemaining(until: schedule.date, from: context.date),
                                 color: palette.selection)
                } else {
                    countdownRow(title: "暂无近期日程", subtitle: "日程", remaining: nil, color: palette.selection)
                }
            }
        }
    }

    private func dateRow(_ label: String, occasion: CalendarOccasion?, color: Color) -> some View {
        let calendar = CalendarDates.gregorian
        let subtitle = occasion.map { event in
            let year = calendar.component(.year, from: event.date)
            let month = calendar.component(.month, from: event.date)
            let day = calendar.component(.day, from: event.date)
            let monthDay = "\(month)月\(day)日"
            let date = year == calendar.component(.year, from: today) ? monthDay : "\(year)年\(monthDay)"
            return "\(label) · \(date)"
        } ?? label
        let days = occasion.flatMap { calendar.dateComponents([.day], from: today, to: $0.date).day }
        let remaining = days.map { $0 == 0 ? "今天" : "\($0) 天" }
        return countdownRow(title: occasion?.name ?? "暂无已收录日期", subtitle: subtitle, remaining: remaining, color: color)
    }

    private func countdownRow(title: String, subtitle: String, remaining: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(remaining == nil ? palette.secondary : palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let remaining {
                    Text(remaining)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.primary)
                        .fixedSize()
                }
            }

            Text(subtitle)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(color)
        }
        .help("\(title) · \(subtitle)")
        .frame(height: 44)
        .padding(.horizontal, 9)
        .background(palette.cell, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
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
