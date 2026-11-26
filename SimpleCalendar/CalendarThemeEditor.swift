import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct CalendarThemeEditor: View {
    @ObservedObject var settings: CalendarSettings
    @ObservedObject var model: CalendarModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var source: String
    @State private var previewTheme: CalendarCustomTheme?
    @State private var validation: Validation?
    @State private var application: ApplicationPreview?
    @State private var isDark = false
    @State private var previewID = ""
    @State private var error: String?
    @State private var status: String?
    @State private var previewFailure: String?
    @State private var previewCanvasUnavailable = false
    @State private var previewRevision = UUID()
    @State private var showingThemeImporter = false
    @StateObject private var scriptEditor = ThemeScriptEditorController()

    private static let maximumSourceBytes = 65_536

    private struct Validation: Identifiable {
        let id = UUID()
        let source: String
        let apply: Bool
    }

    private struct ApplicationPreview: Identifiable {
        let id = UUID()
        let theme: CalendarCustomTheme
        let isDark: Bool
        let remainingAppearances: [Bool]
    }

    private struct PreviewItem: Identifiable {
        let id: String
        let name: String
        let background: CalendarThemeRules.Background?
        var subtitleColor: String? = nil
        var badge: CalendarThemeRules.BadgeStyle? = nil
        var dotColor: String? = nil
        var row: CalendarThemeRules.ScheduleRule.RowStyle? = nil
    }

    private var isBusy: Bool { validation != nil || application != nil }

    init(settings: CalendarSettings, model: CalendarModel) {
        self.settings = settings
        self.model = model
        _source = State(initialValue: settings.customTheme?.source ?? (try? Self.defaultSource()) ?? "")
        _previewTheme = State(initialValue: settings.customTheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("自定义主题").font(.title2)
                Spacer()
                Button("从文件载入…") { showingThemeImporter = true }
                    .disabled(isBusy)
                Button("载入默认主题") { loadDefaultTheme() }
                    .disabled(isBusy)
                Menu("规则参考") {
                    referenceMenu("节日 ID", entries: CalendarThemeRules.festivalNames)
                    referenceMenu("节气 ID", entries: CalendarThemeRules.solarTermNames)
                    scheduleMenu("插入日程规则", action: insertScheduleRule)
                        .help("规则会插到默认主题的日程数组内。自定义脚本可以先把光标放在 schedules 数组中。")
                    scheduleMenu("复制日程匹配条件") { schedule in
                        copy("match: { id: \"\(schedule.id.uuidString)\" }")
                    }
                }
                .disabled(isBusy)
            }

            ThemeScriptEditor(source: $source, isEditable: !isBusy, controller: scriptEditor)
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
                .border(Color.secondary.opacity(0.25))

            HStack(alignment: .top, spacing: 16) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    if let error {
                        ScrollView {
                            Text(error).foregroundStyle(.red).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if let application {
                        Text(application.isDark ? "正在检查深色绘制…" : "正在检查浅色绘制…")
                            .foregroundStyle(.secondary)
                    } else if let status {
                        Text(status).foregroundStyle(.secondary)
                    } else if previewTheme?.source != source {
                        Text("点击预览检查脚本和背景效果。").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, maxHeight: 88, alignment: .topLeading)
            }

            HStack {
                Button("停用主题") { restoreDefault() }
                    .disabled(settings.customTheme == nil || isBusy)
                Spacer()
                if isBusy { ProgressView().controlSize(.small) }
                Button("关闭") {
                    cancelPendingWork()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("预览") { prepare(apply: false) }
                    .disabled(isBusy)
                Button("应用") { prepare(apply: true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
            }
        }
        .onChange(of: source) { _ in
            error = nil
            status = nil
        }
        .onDisappear { cancelPendingWork() }
        .fileImporter(isPresented: $showingThemeImporter, allowedContentTypes: [.javaScript]) { result in
            importTheme(result)
        }
        .task(id: application?.id) {
            guard let application else { return }
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            previewFailed("预览绘制超时，请重新预览。", source: application.theme.source, application: application, fatal: true)
        }
        .padding(18)
        .frame(width: 720, height: 490)
        .background {
            if let validation {
                CalendarThemeCanvas(
                    request: .validate(validation.source),
                    onValidation: { rules in validated(rules, request: validation) },
                    onFailure: { message in
                        guard self.validation?.id == validation.id else { return }
                        self.validation = nil
                        error = message
                    }
                )
                .id(validation.id)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
        }
    }

    private var preview: some View {
        let application = application
        let dark = application?.isDark ?? isDark
        let theme = application?.theme ?? previewTheme
        let allItems: [PreviewItem] = theme.map { previewItems(for: $0.rules(isDark: dark)) } ?? []
        let items = application == nil ? allItems : allItems.filter { $0.background?.painter != nil }
        let item = items.first { $0.id == previewID } ?? items.first
        let palette = CalendarPalette(isDark: dark, theme: settings.theme)
        let size = CGSize(width: 111, height: 64)

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Picker("预览外观", selection: Binding(get: { dark }, set: { isDark = $0 })) {
                    Text("浅色").tag(false)
                    Text("深色").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(isBusy)

                if !items.isEmpty {
                    Picker("预览对象", selection: Binding(
                        get: { item?.id ?? "" },
                        set: { previewID = $0 }
                    )) {
                        ForEach(items) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                    .labelsHidden()
                    .disabled(isBusy)
                } else {
                    Text(previewTheme == nil ? "暂无预览" : "当前外观未配置背景")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 166)

            VStack(alignment: .leading, spacing: 4) {
                previewCell(item, theme: theme, items: items, application: application,
                            palette: palette, size: size)
                previewDetails(item, palette: palette)
            }
        }
    }

    private func previewCell(_ item: PreviewItem?, theme: CalendarCustomTheme?, items: [PreviewItem],
                             application: ApplicationPreview?, palette: CalendarPalette, size: CGSize) -> some View {
        VStack(spacing: 2) {
            Text("22").font(.system(size: 18)).foregroundStyle(palette.primary)
            Text(item?.name ?? "廿二")
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(Color(themeHex: item?.subtitleColor) ?? palette.secondary)
                .padding(.horizontal, 4)
        }
        .frame(width: size.width, height: size.height)
        .background {
            if !previewCanvasUnavailable, let theme, let item, let painter = item.background?.painter {
                previewCanvas(theme, item: item, painter: painter, items: items,
                              application: application, isDark: palette.isDark, size: size)
            } else {
                item?.background?.swiftUIColor ?? palette.surface
            }
        }
        .background(palette.surface)
        .overlay(alignment: .topLeading) {
            if let dotColor = Color(themeHex: item?.dotColor) {
                Circle().fill(dotColor).frame(width: 4, height: 4).padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }

    private func previewCanvas(_ theme: CalendarCustomTheme, item: PreviewItem, painter: String, items: [PreviewItem],
                               application: ApplicationPreview?, isDark: Bool, size: CGSize) -> some View {
        let frame = CGRect(origin: .zero, size: size)
        let tiles: [CalendarThemeTile]
        if application == nil {
            tiles = [CalendarThemeTile(id: item.id, painter: painter, frame: frame)]
        } else {
            tiles = items.compactMap { entry in
                guard let painter = entry.background?.painter else { return nil }
                return CalendarThemeTile(id: entry.id, painter: painter, frame: frame)
            }
        }

        return CalendarThemeCanvas(
            request: .draw(theme, .init(
                tiles: tiles, isDark: isDark, reduceMotion: reduceMotion,
                previewTileID: application == nil ? nil : item.id
            )),
            onFailure: { previewFailed($0, source: theme.source, application: application, fatal: true) },
            onDrawingError: { key, message in
                let name = items.first { $0.id == key.id }?.name
                let details = name.map { "\($0)绘制失败：\(message)" } ?? message
                previewFailed(details, source: theme.source, application: application, fatal: false)
            },
            onPreviewPassed: {
                if let application { applicationPreviewPassed(application) }
            }
        )
        .id(application?.id ?? previewRevision)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func previewDetails(_ item: PreviewItem?, palette: CalendarPalette) -> some View {
        if let item, let badge = item.badge {
            let isSolarTerm = item.id.hasPrefix("solarTerm.")
            let festival = Festival(rawValue: String(item.id.dropFirst("festival.".count)))
            let fallbackIcon = isSolarTerm ? "leaf" : festival?.symbol ?? "flag.fill"
            let fallbackColor = isSolarTerm ? palette.solarTerm : festival.map(palette.festival) ?? palette.weekend
            let color = Color(themeHex: badge.color) ?? fallbackColor
            Label(item.name, systemImage: badge.icon ?? fallbackIcon)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color.opacity(0.14), in: Capsule())
        } else if let item, let row = item.row {
            HStack(spacing: 5) {
                if let icon = row.icon { Image(systemName: icon).accessibilityHidden(true) }
                Text(item.name).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(Color(themeHex: row.titleColor) ?? palette.primary)
        }
    }

    private func previewItems(for rules: CalendarThemeRules) -> [PreviewItem] {
        let festivals = rules.festivals.keys.sorted().compactMap { id -> PreviewItem? in
            guard let style = rules.festivals[id] else { return nil }
            return PreviewItem(id: "festival." + id, name: CalendarThemeRules.festivalNames[id] ?? id,
                               background: style.background, subtitleColor: style.subtitleColor, badge: style.badge)
        }
        let solarTerms = rules.solarTerms.keys.sorted().compactMap { id -> PreviewItem? in
            guard let style = rules.solarTerms[id] else { return nil }
            return PreviewItem(id: "solarTerm." + id, name: CalendarThemeRules.solarTermNames[id] ?? id,
                               background: style.background, subtitleColor: style.subtitleColor, badge: style.badge)
        }
        let schedules = rules.identifiedSchedules.enumerated().map { index, entry in
            let (key, rule) = entry
            let name: String
            if let id = rule.match.id {
                name = model.schedules.first { $0.id == id }?.displayTitle ?? "日程规则 \(index + 1)"
            } else {
                name = rule.match.titleEquals ?? rule.match.titleContains ?? "日程规则 \(index + 1)"
            }
            return PreviewItem(id: key, name: name, background: rule.background, dotColor: rule.dotColor, row: rule.row)
        }
        return festivals + solarTerms + schedules
    }

    private func referenceMenu(_ label: String, entries: [String: String]) -> some View {
        Menu(label) {
            ForEach(entries.keys.sorted(), id: \.self) { id in
                Button("\(entries[id] ?? id) · \(id)") { copy(id) }
            }
        }
    }

    private func scheduleMenu(_ title: String, action: @escaping (CalendarSchedule) -> Void) -> some View {
        Menu(title) {
            ForEach(model.schedules) { schedule in
                let date = schedule.date.formatted(.dateTime.month().day().hour().minute())
                Button("\(schedule.displayTitle) · \(date)") { action(schedule) }
            }
        }
        .disabled(model.schedules.isEmpty)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "已复制 \(text)"
    }

    private func insertScheduleRule(_ schedule: CalendarSchedule) {
        let rule = "      { match: { id: \"\(schedule.id.uuidString)\" }, dotColor: \"#B52D78\" },\n"
        if scriptEditor.insert(rule, before: "// 在此插入日程规则") {
            error = nil
        } else {
            error = "无法插入日程规则。请将光标放在 schedules 数组内后重试。"
        }
    }

    private enum ThemeFileError: LocalizedError {
        case unavailableDefault, unsupportedFile, tooLarge, invalidEncoding

        var errorDescription: String? {
            switch self {
            case .unavailableDefault: return "找不到内置默认主题。"
            case .unsupportedFile: return "请选择一个 .js 主题文件。"
            case .tooLarge: return "主题脚本最大为 64 KB。"
            case .invalidEncoding: return "主题文件需要使用 UTF-8 编码。"
            }
        }
    }

    private static func readThemeSource(from url: URL) throws -> String {
        guard url.pathExtension.lowercased() == "js", try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw ThemeFileError.unsupportedFile
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximumSourceBytes + 1) ?? Data()
        guard data.count <= maximumSourceBytes else { throw ThemeFileError.tooLarge }
        guard let source = String(data: data, encoding: .utf8) else { throw ThemeFileError.invalidEncoding }
        return source
    }

    private static func defaultSource() throws -> String {
        guard let url = Bundle.main.url(forResource: "CalendarDefaultTheme", withExtension: "js") else {
            throw ThemeFileError.unavailableDefault
        }
        return try readThemeSource(from: url)
    }

    private func loadDefaultTheme() {
        do {
            source = try Self.defaultSource()
            error = nil
            status = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importTheme(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            source = try Self.readThemeSource(from: url)
            error = nil
            status = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func prepare(apply: Bool) {
        guard !isBusy else { return }
        error = nil
        status = nil
        guard source.utf8.count <= Self.maximumSourceBytes else {
            error = ThemeFileError.tooLarge.localizedDescription
            return
        }
        if apply, let previewTheme, previewTheme.source == source {
            if let previewFailure {
                error = previewFailure
            } else {
                beginApplicationPreview(previewTheme)
            }
        } else {
            validation = Validation(source: source, apply: apply)
        }
    }

    private func validated(_ rules: CalendarThemeAppearances, request: Validation) {
        guard validation?.id == request.id else { return }
        validation = nil
        guard source == request.source else { return }
        let theme = CalendarCustomTheme(source: source, rules: rules)
        previewTheme = theme
        previewFailure = nil
        previewCanvasUnavailable = false
        previewRevision = UUID()
        if request.apply {
            beginApplicationPreview(theme)
        } else {
            status = "预览已更新。"
        }
    }

    private func beginApplicationPreview(_ theme: CalendarCustomTheme) {
        let appearances = [false, true].filter { dark in
            previewItems(for: theme.rules(isDark: dark)).contains { $0.background?.painter != nil }
        }
        advanceApplicationPreview(theme, appearances: appearances)
    }

    private func advanceApplicationPreview(_ theme: CalendarCustomTheme, appearances: [Bool]) {
        if let appearance = appearances.first {
            application = ApplicationPreview(theme: theme, isDark: appearance,
                                             remainingAppearances: Array(appearances.dropFirst()))
        } else {
            application = nil
            save(theme)
        }
    }

    private func applicationPreviewPassed(_ attempt: ApplicationPreview) {
        guard application?.id == attempt.id, source == attempt.theme.source else { return }
        advanceApplicationPreview(attempt.theme, appearances: attempt.remainingAppearances)
    }

    private func previewFailed(_ message: String, source: String, application attempt: ApplicationPreview?, fatal: Bool) {
        guard validation == nil, previewTheme?.source == source, application?.id == attempt?.id else { return }
        application = nil
        if fatal || attempt != nil { previewCanvasUnavailable = true }
        let appearance = attempt.map { $0.isDark ? "深色预览：" : "浅色预览：" } ?? ""
        let message = appearance + message
        previewFailure = message
        if self.source == source {
            error = message
            status = nil
        }
    }

    private func save(_ theme: CalendarCustomTheme) {
        do {
            try settings.applyCustomTheme(theme)
            status = "主题已应用。"
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func restoreDefault() {
        settings.resetCustomTheme()
        previewTheme = nil
        previewFailure = nil
        previewCanvasUnavailable = false
        error = nil
        status = "已恢复默认外观，编辑器保留当前脚本。"
    }

    private func cancelPendingWork() {
        validation = nil
        application = nil
    }
}

@MainActor
private final class ThemeScriptEditorController: ObservableObject {
    weak var textView: NSTextView?

    func insert(_ rule: String, before marker: String) -> Bool {
        guard let textView, textView.isEditable, let storage = textView.textStorage else { return false }
        let text = textView.string as NSString
        let markerRange = text.range(of: marker)
        let offset: Int
        if markerRange.location != NSNotFound {
            offset = text.lineRange(for: markerRange).location
        } else {
            offset = textView.selectedRange().location
        }
        guard offset <= text.length else { return false }

        let lineStart = offset == 0 || text.character(at: offset - 1) == 10
        let insertion = lineStart ? rule : "\n" + rule
        let range = NSRange(location: offset, length: 0)
        guard textView.shouldChangeText(in: range, replacementString: insertion) else { return false }
        storage.replaceCharacters(in: range, with: insertion)
        let caret = NSRange(location: offset + insertion.utf16.count, length: 0)
        textView.setSelectedRange(caret)
        textView.didChangeText()
        textView.window?.makeFirstResponder(textView)
        textView.scrollRangeToVisible(caret)
        return true
    }
}

@MainActor
private struct ThemeScriptEditor: NSViewRepresentable {
    @Binding var source: String
    let isEditable: Bool
    let controller: ThemeScriptEditorController

    func makeCoordinator() -> Coordinator { Coordinator(source: $source) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.string = source
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.setAccessibilityLabel("JavaScript 主题代码")
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.source = $source
        if textView.isEditable != isEditable { textView.isEditable = isEditable }
        if textView.string != source {
            textView.string = source
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var source: Binding<String>

        init(source: Binding<String>) { self.source = source }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, source.wrappedValue != textView.string else { return }
            source.wrappedValue = textView.string
        }
    }
}
