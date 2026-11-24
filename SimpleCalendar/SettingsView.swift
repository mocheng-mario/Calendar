import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: Hashable {
    case general, appearance, calendar, schedule
}

struct SettingsView: View {
    @ObservedObject var settings: CalendarSettings
    @ObservedObject var model: CalendarModel
    let openSchedule: () -> Void
    @State private var section: SettingsSection = .appearance
    @State private var scheduleSearch = ""
    @State private var schedulePendingDeletion: CalendarSchedule?
    @State private var clockDropTarget: ClockField?
    @State private var remoteAddress = ""
    @State private var showingHolidayImport = false
    @State private var showingHolidayTemplate = false
    @State private var holidayError: String?
    @State private var holidayUpdateMessage: String?

    private static let clockDragPrefix = "simplecalendar-clock-field:"

    init(settings: CalendarSettings, model: CalendarModel, openSchedule: @escaping () -> Void) {
        self.settings = settings
        self.model = model
        self.openSchedule = openSchedule
    }

    var body: some View {
        TabView(selection: $section) {
            general
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsSection.general)
            appearance
                .tabItem { Label("外观", systemImage: "paintpalette") }
                .tag(SettingsSection.appearance)
            calendar
                .tabItem { Label("日历", systemImage: "calendar") }
                .tag(SettingsSection.calendar)
            schedule
                .tabItem { Label("日程", systemImage: "clock") }
                .tag(SettingsSection.schedule)
        }
        .frame(width: 618, height: 377)
        .padding(12)
        .environment(\.calendar, CalendarDates.localGregorian)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .fileImporter(isPresented: $showingHolidayImport, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
            do {
                try settings.importHolidays(from: result.get())
                holidayError = nil
            } catch {
                holidayError = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $showingHolidayTemplate, document: HolidayTemplate(), contentType: .json,
                      defaultFilename: "holiday-template") { result in
            if case .failure(let error) = result {
                holidayError = error.localizedDescription
            }
        }
        .alert("删除日程？", isPresented: Binding(
            get: { schedulePendingDeletion != nil },
            set: { if !$0 { schedulePendingDeletion = nil } }
        ), presenting: schedulePendingDeletion) { schedule in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { model.removeSchedule(schedule.id) }
        } message: { schedule in
            Text("\(schedule.displayTitle)\n\(scheduleDateLabel(schedule.date))")
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("登录后启动 Calendar", isOn: Binding(
                get: { settings.launchesAtLogin },
                set: { settings.setLaunchAtLogin($0) }
            ))

            if settings.loginItemStatus == .requiresApproval {
                Text("请在系统设置的登录项中允许 Calendar 启动。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("打开登录项设置…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = settings.loginItemError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var appearance: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 13) {
                Text("主题色").font(.headline)
                HStack(spacing: 10) {
                    ForEach(CalendarTheme.allCases) { theme in
                        Button {
                            settings.theme = theme
                        } label: {
                            Circle()
                                .fill(theme.fill)
                                .frame(width: 23, height: 23)
                                .overlay {
                                    if settings.theme == theme {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color(hex: 0x20242A))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(theme.label)
                        .accessibilityLabel(Text(theme.label))
                        .accessibilityAddTraits(settings.theme == theme ? .isSelected : [])
                    }
                }
                Text("菜单栏预览").font(.headline)
                clockPreview
                if settings.clockFields.contains(where: { $0.field == .custom && $0.isEnabled }) {
                    TextField("自定义格式", text: $settings.customClockFormat, prompt: Text("yyyy-MM-dd HH:mm"))
                }

                Divider()
                calendarLayoutSettings
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("状态栏格式").font(.headline)
                Text("勾选要显示的项目，拖动右侧手柄排序。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                ForEach(settings.clockFields) { option in
                    clockFieldRow(option)
                }
            }
            .frame(width: 258, alignment: .leading)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var calendarLayoutSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("月历布局").font(.headline)

            Picker("详情栏", selection: $settings.popoverLayout.detailsSide) {
                Text("左侧").tag(CalendarPopoverLayout.Side.left)
                Text("右侧").tag(CalendarPopoverLayout.Side.right)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                dimensionField("月历宽度", value: $settings.popoverLayout.calendarWidth,
                               minimum: CalendarPopoverLayout.minimumCalendarWidth)
                dimensionField("详情栏宽度", value: $settings.popoverLayout.detailsWidth,
                               minimum: CalendarPopoverLayout.minimumDetailsWidth)
                dimensionField("高度", value: $settings.popoverLayout.height, minimum: CalendarPopoverLayout.minimumHeight)
            }

            Toggle("允许拖动缩放", isOn: $settings.popoverLayout.allowsDragResize)
        }
    }

    private func dimensionField(_ label: String, value: Binding<Int>, minimum: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption)
            TextField(label, value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = max(minimum, $0) }),
                      format: .number.grouping(.never))
                .labelsHidden()
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func clockFieldRow(_ option: ClockFieldOption) -> some View {
        let isLastEnabled = option.isEnabled && !settings.clockFields.contains { $0.id != option.id && $0.isEnabled }
        return HStack(spacing: 6) {
            Toggle(isOn: Binding(get: {
                settings.clockFields.first { $0.id == option.id }?.isEnabled ?? false
            }, set: { enabled in
                settings.setClockField(option.field, enabled: enabled)
            })) {
                Text(option.field.label)
            }
            .toggleStyle(.checkbox)
            .disabled(isLastEnabled)

            Spacer(minLength: 4)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 25, height: 25)
                .contentShape(Rectangle())
                .draggable(Self.clockDragPrefix + option.field.rawValue)
                .help("拖动 \(option.field.label)")
                .accessibilityLabel(Text("拖动 \(option.field.label) 排序"))
        }
        .frame(minHeight: 25)
        .background {
            if clockDropTarget == option.field {
                RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.15))
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let token = items.first, token.hasPrefix(Self.clockDragPrefix),
                  let field = ClockField(rawValue: String(token.dropFirst(Self.clockDragPrefix.count))) else { return false }
            return withAnimation(.easeInOut(duration: 0.15)) { settings.moveClockField(field, to: option.field) }
        } isTargeted: { isTargeted in
            if isTargeted {
                clockDropTarget = option.field
            } else if clockDropTarget == option.field {
                clockDropTarget = nil
            }
        }
    }

    private var clockPreview: some View {
        let items = settings.clockItems(at: .now)
        return HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                switch items[index] {
                case .icon:
                    Image("MenuBarIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .accessibilityLabel("日历图标")
                case .text(let text):
                    Text(text)
                        .monospacedDigit()
                        .lineLimit(2)
                }
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("一周从", selection: $settings.firstWeekday) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text("星期\(CalendarDay.weekdayNames[weekday - 1])").tag(weekday)
                    }
                }
                .fixedSize()
                Spacer()
                Button("下载 JSON 模板…") { showingHolidayTemplate = true }
            }

            Divider()

            HStack {
                Text("假期来源").font(.headline)
                Spacer()
                Text("\(settings.holidaySelection.sources.count) / \(HolidaySelection.maximumSources) 自定义")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 3) {
                defaultHolidaySourceRow
                ForEach(settings.holidaySelection.sources) { source in
                    holidaySourceRow(source)
                }
            }

            HStack(spacing: 8) {
                TextField("远程地址", text: $remoteAddress, prompt: Text("https://example.com/2027.json"))
                    .labelsHidden()
                    .onSubmit(addRemoteSource)
                Button("添加远程", action: addRemoteSource)
                    .disabled(remoteAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("导入 JSON…") { showingHolidayImport = true }
            }
            .disabled(!settings.holidaySelection.canAddSource)

            Text(holidayError ?? holidayUpdateMessage ?? "选择一个来源生效。远程文件会缓存，缺少的年份使用 holiday-cn。")
                .font(.caption)
                .foregroundStyle(holidayError == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var defaultHolidaySourceRow: some View {
        HStack(spacing: 8) {
            sourceChoice("holiday-cn（默认）", id: nil)
            Spacer(minLength: 5)
            Text(settings.defaultHolidays.years.map(String.init).joined(separator: "、"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button(settings.isRefreshingDefaultHolidays ? "更新中…" : "更新") {
                holidayError = nil
                holidayUpdateMessage = nil
                Task {
                    do {
                        if try await settings.refreshDefaultHolidays() {
                            holidayUpdateMessage = "holiday-cn 已更新。"
                        }
                    } catch {
                        holidayError = error.localizedDescription
                    }
                }
            }
            .disabled(settings.isRefreshingDefaultHolidays)
        }
        .controlSize(.small)
    }

    private func sourceChoice(_ name: String, id: UUID?) -> some View {
        let isActive = settings.holidaySelection.activeID == id
        return Button {
            settings.selectHolidaySource(id)
            holidayError = nil
        } label: {
            Label(name, systemImage: isActive ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .frame(minHeight: 24)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func holidaySourceRow(_ source: SavedHolidaySource) -> some View {
        let years = source.calendar.years.map(String.init).joined(separator: "、")
        return HStack(spacing: 8) {
            sourceChoice(source.name, id: source.id)
            if let url = source.remoteURL {
                Text(url.path.isEmpty ? url.absoluteString : url.path)
                    .truncationMode(.middle)
                    .help(url.absoluteString)
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 5)
            Text(years.isEmpty ? "未下载" : years)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
            if source.remoteURL != nil {
                let isRefreshing = settings.refreshingSourceIDs.contains(source.id)
                Button(isRefreshing ? "刷新中…" : "刷新") { refreshSource(source.id) }
                    .disabled(isRefreshing)
            }
            Button("移除", role: .destructive) {
                settings.removeHolidaySource(source.id)
                holidayError = nil
            }
        }
        .controlSize(.small)
    }

    private func addRemoteSource() {
        do {
            let id = try settings.addRemoteHolidaySource(remoteAddress)
            remoteAddress = ""
            refreshSource(id)
        } catch {
            holidayError = error.localizedDescription
        }
    }

    private func refreshSource(_ id: UUID) {
        holidayError = nil
        holidayUpdateMessage = nil
        Task {
            do {
                try await settings.refreshHolidaySource(id)
            } catch {
                if settings.holidaySelection.sources.contains(where: { $0.id == id }) {
                    holidayError = error.localizedDescription
                }
            }
        }
    }

    private var schedule: some View {
        let query = scheduleSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = query.isEmpty ? model.schedules : model.schedules.filter {
            $0.displayTitle.localizedStandardContains(query) || scheduleDateLabel($0.date).localizedStandardContains(query)
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索日程", text: $scheduleSearch, prompt: Text("搜索标题或日期"))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                    if !scheduleSearch.isEmpty {
                        Button { scheduleSearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Button(action: openSchedule) { Label("添加日程…", systemImage: "plus") }
            }

            if results.isEmpty {
                Text(query.isEmpty ? "暂无日程" : "没有匹配的日程")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { schedule in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(schedule.displayTitle).lineLimit(1)
                            Text(scheduleDateLabel(schedule.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                        Button("删除", role: .destructive) { schedulePendingDeletion = schedule }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("删除 \(schedule.displayTitle)"))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func scheduleDateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN")))
    }
}

struct ScheduleEditorView: View {
    @ObservedObject var model: CalendarModel
    let close: () -> Void
    @State private var selectedDay: Date
    @State private var timeText: String
    @State private var title = ""
    @FocusState private var titleIsFocused: Bool

    init(model: CalendarModel, date: Date, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _selectedDay = State(initialValue: date)
        _timeText = State(initialValue: Self.timeLabel(for: date))
    }

    var body: some View {
        let scheduleDate = dateWithEnteredTime
        let showsInvalidTime = scheduleDate == nil && !timeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let timeHelp = showsInvalidTime && Self.parseTime(timeText) != nil
            ? "所选日期没有这个本地时间。"
            : "24 小时制，请输入类似 09:30 或 0930 的时间。"
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("标题（可选）").font(.callout)
                TextField("标题", text: $title, prompt: Text("例如：交房租"))
                    .labelsHidden()
                    .focused($titleIsFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("日期").font(.callout)
                    DatePicker("日期", selection: $selectedDay, displayedComponents: .date)
                        .labelsHidden()
                }

                HStack(spacing: 10) {
                    Text("时间").font(.callout)
                    TextField("时间", text: $timeText, prompt: Text("09:30"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .frame(width: 86)
                        .onSubmit(save)
                    Button("当前时间") { timeText = Self.timeLabel(for: .now) }
                        .controlSize(.small)
                }

                Text(timeHelp)
                    .font(.caption)
                    .foregroundStyle(showsInvalidTime ? Color.red : Color.secondary)
            }

            HStack {
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button("添加", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(scheduleDate.map { model.hasSchedule(at: $0, title: title) } ?? true)
            }
        }
        .padding(20)
        .frame(width: 340)
        .environment(\.calendar, CalendarDates.localGregorian)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .onAppear { titleIsFocused = true }
    }

    private var dateWithEnteredTime: Date? {
        guard let parts = Self.parseTime(timeText) else { return nil }
        let calendar = CalendarDates.localGregorian
        guard let result = calendar.date(bySettingHour: parts.hour, minute: parts.minute, second: 0, of: selectedDay,
                                         matchingPolicy: .strict), calendar.isDate(result, inSameDayAs: selectedDay) else { return nil }
        return result
    }

    private func save() {
        guard let date = dateWithEnteredTime, !model.hasSchedule(at: date, title: title) else { return }
        model.addSchedule(at: date, title: title)
        close()
    }

    private static func timeLabel(for date: Date) -> String {
        let parts = CalendarDates.localGregorian.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func parseTime(_ input: String) -> (hour: Int, minute: Int)? {
        let text = (input.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? input)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fields: [Substring]
        if !text.contains(":"), (3...4).contains(text.count) {
            let index = text.index(text.endIndex, offsetBy: -2)
            fields = [text[..<index], text[index...]]
        } else {
            fields = text.split(separator: ":", omittingEmptySubsequences: false)
        }
        guard fields.count == 2, (1...2).contains(fields[0].count), (1...2).contains(fields[1].count),
              fields.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let hour = Int(fields[0]), (0..<24).contains(hour),
              let minute = Int(fields[1]), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }
}

private struct HolidayTemplate: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    private let data: Data

    init() {
        let year = CalendarDates.localGregorian.component(.year, from: .now)
        data = Data("""
        {
          "year": \(year),
          "days": [
            { "date": "\(year)-01-01", "name": "元旦", "isOffDay": true }
          ]
        }
        """.utf8)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
