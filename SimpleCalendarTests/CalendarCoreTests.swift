import Foundation
import XCTest

final class CalendarCoreTests: XCTestCase {
    func testMonthGridHasSixWeeksAndRespectsTheFirstWeekday() async throws {
        try await MainActor.run {
            try withCalendarModel { model in
                // March 2026 starts on a Sunday, so a Monday-start grid includes six days from February.
                model.select(try day("2026-03-01"))
                let mondayGrid = model.days(startingOn: 2)
                let sundayGrid = model.days(startingOn: 1)
                XCTAssertEqual(mondayGrid.count, 42)
                XCTAssertEqual(sundayGrid.count, 42)
                XCTAssertEqual(mondayGrid.first?.date, try day("2026-02-23"))
                XCTAssertEqual(mondayGrid.last?.date, try day("2026-04-05"))
                XCTAssertEqual(sundayGrid.first?.date, try day("2026-03-01"))
                XCTAssertEqual(mondayGrid.filter(\.isCurrentMonth).count, 31)
            }
        }
    }

    func testMovingMonthsHandlesLeapDayAndTheYearBoundary() async throws {
        try await MainActor.run {
            try withCalendarModel { model in
                model.select(try day("2024-01-31"))
                model.moveMonth(by: 1)
                XCTAssertEqual(model.selectedDate, try day("2024-02-29"))

                model.select(try day("2026-12-31"))
                model.moveMonth(by: 1)
                XCTAssertEqual(model.selectedDate, try day("2027-01-31"))
                XCTAssertNil(CalendarDates.parseDay("2026-02-29"))
            }
        }
    }

    func testRefreshingTodayKeepsASeparatelySelectedDate() async throws {
        try await MainActor.run {
            try withCalendarModel { model in
                let first = try day("2026-06-01")
                let next = try day("2026-06-02")
                model.refreshToday(at: first)
                let selected = try day("2026-06-10")
                model.select(selected)

                model.refreshToday(at: next)
                XCTAssertEqual(model.today, CalendarDates.localDay(at: next))
                XCTAssertEqual(model.selectedDate, selected)
            }
        }
    }

    func testLocalCivilDayRespectsTimeZonesAcrossDaylightSaving() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let formatter = ISO8601DateFormatter()
        let before = try XCTUnwrap(formatter.date(from: "2026-03-08T09:59:00Z"))
        let after = try XCTUnwrap(formatter.date(from: "2026-03-08T10:01:00Z"))
        let lateEvening = try XCTUnwrap(formatter.date(from: "2026-03-09T06:30:00Z"))
        let march8 = try day("2026-03-08")

        XCTAssertEqual(CalendarDates.localDay(at: before, in: losAngeles), march8)
        XCTAssertEqual(CalendarDates.localDay(at: after, in: losAngeles), march8)
        XCTAssertEqual(CalendarDates.localDay(at: lateEvening, in: losAngeles), march8)
        XCTAssertEqual(CalendarDates.localDay(at: lateEvening, in: utc), try day("2026-03-09"))
    }

    func testLunarDateRecognizesLeapMonthAndSpringFestival() throws {
        let leapMonth = try XCTUnwrap(LunarDate(date: try day("2025-07-25")))
        XCTAssertTrue(leapMonth.isLeapMonth)
        XCTAssertEqual(leapMonth.month, 6)
        XCTAssertEqual(leapMonth.day, 1)

        let springFestival = CalendarDay(date: try day("2026-02-17"), isCurrentMonth: true)
        XCTAssertEqual(springFestival.lunarDate?.dayName, "初一")
        XCTAssertEqual(springFestival.festival()?.name, "春节")

        let eve = CalendarDay(date: try day("2026-02-16"), isCurrentMonth: true)
        XCTAssertEqual(eve.lunarDate?.day, 29)
        XCTAssertEqual(eve.festival()?.name, "除夕")
        XCTAssertEqual(HolidayCalendar.bundled.statutoryOccasion(on: eve.date)?.name, "春节")
    }

    func testBundledScheduleIncludesQingmingAndWeekendMakeupWork() throws {
        let holidaySchedule = HolidayCalendar.bundled
        let qingming = try day("2026-04-05")
        let term = SolarTerms.bundled.name(on: qingming)
        XCTAssertEqual(term, "清明")
        XCTAssertEqual(CalendarDay(date: qingming, isCurrentMonth: true).festival(solarTerm: term)?.name, "清明节")
        XCTAssertEqual(holidaySchedule[qingming]?.name, "清明节")
        XCTAssertEqual(holidaySchedule[qingming]?.isOffDay, true)

        let makeupWork = try day("2026-09-20")
        XCTAssertTrue(CalendarDay(date: makeupWork, isCurrentMonth: true).isWeekend)
        XCTAssertEqual(holidaySchedule[makeupWork]?.isOffDay, false)
        for date in 1...7 {
            XCTAssertEqual(holidaySchedule[try day("2026-10-0\(date)")]?.isOffDay, true)
        }
    }

    func testCountdownIgnoresNonStatutoryDaysInTheHolidayBreak() throws {
        let endOfNationalDay = try day("2026-10-04")
        let next = HolidayCalendar.bundled.nextStatutoryDay(from: endOfNationalDay)
        XCTAssertEqual(next?.date, try day("2027-01-01"))
        XCTAssertEqual(next?.name, "元旦")
    }

    func testImportedYearOverridesOnlyTheSameYear() throws {
        let data = Data(#"{"year":2027,"days":[{"date":"2027-01-01","name":"元旦","isOffDay":false}]}"#.utf8)
        let document = try JSONDecoder().decode(HolidayYear.self, from: data)
        let calendar = HolidayCalendar.bundled.replacingYears(with: HolidayCalendar(documents: [document]))

        XCTAssertEqual(calendar[try day("2027-01-01")]?.isOffDay, false)
        XCTAssertNil(calendar[try day("2027-02-05")])
        XCTAssertEqual(calendar[try day("2026-01-01")]?.isOffDay, true)
    }

    func testHistoricalStatutoryDatesFollowTheRulesInEffectThatYear() throws {
        let calendar = HolidayCalendar(documents: [])
        XCTAssertEqual(calendar.statutoryOccasion(on: try day("2007-05-03"))?.name, "劳动节")
        XCTAssertNil(calendar.statutoryOccasion(on: try day("2008-05-03")))
        XCTAssertEqual(calendar.statutoryOccasion(on: try day("2008-02-06"))?.name, "春节")
        XCTAssertNil(calendar.statutoryOccasion(on: try day("2014-01-30")))
        XCTAssertEqual(calendar.statutoryOccasion(on: try day("2026-05-02"))?.name, "劳动节")
    }

    func testDownloadedSolarTermsRequireACompleteUniqueYear() throws {
        let url = try XCTUnwrap(Bundle(for: CalendarCoreTests.self).url(
            forResource: "solar-terms", withExtension: "csv", subdirectory: "CalendarData"
        ))
        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("2028-") }.map { entry -> String in
            let fields = entry.split(separator: ",")
            let date = fields[0].split(separator: "-")
            let term = fields[1] == "惊蛰" ? "驚蟄" : String(fields[1])
            return "\(date[0])年\(date[1])月\(date[2])日 　 初一 星期一 \(term)"
        }
        let data = Data(lines.joined(separator: "\n").utf8)
        let entries = try XCTUnwrap(SolarTerms.parseObservatoryTable(data, year: 2028))
        XCTAssertEqual(entries.count, 24)
        XCTAssertEqual(SolarTerms(terms: entries).name(on: try day("2028-03-05")), "惊蛰")
        XCTAssertNil(SolarTerms.parseObservatoryTable(Data(lines.dropLast().joined(separator: "\n").utf8), year: 2028))
        XCTAssertNil(SolarTerms.parseObservatoryTable(Data((lines + lines.prefix(1)).joined(separator: "\n").utf8), year: 2028))
        XCTAssertNil(SolarTerms(terms: entries).next(from: try day("2027-12-31")))
    }
}

private func day(_ text: String) throws -> Date {
    try XCTUnwrap(CalendarDates.parseDay(text))
}

@MainActor
private func withCalendarModel(_ body: (CalendarModel) throws -> Void) throws {
    let suite = "SimpleCalendarTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(CalendarModel(defaults: defaults))
}
