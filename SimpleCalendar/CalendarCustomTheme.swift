import AppKit
import SwiftUI
import WebKit

struct CalendarCustomTheme: Codable, Equatable {
    let source: String
    let rules: CalendarThemeAppearances

    func rules(isDark: Bool) -> CalendarThemeRules {
        isDark ? rules.dark : rules.light
    }
}

struct CalendarThemeAppearances: Codable, Equatable {
    let light: CalendarThemeRules
    let dark: CalendarThemeRules

    var withStableSchedulePainters: Self {
        Self(light: light.withStableSchedulePainters(appearance: "light"),
             dark: dark.withStableSchedulePainters(appearance: "dark"))
    }
}

struct CalendarThemeRules: Codable, Equatable {
    struct Background: Codable, Equatable {
        let color: String?
        let painter: String?

        var swiftUIColor: Color? { Color(themeHex: color) }
    }

    struct BadgeStyle: Codable, Equatable {
        let color: String?
        let icon: String?
    }

    struct OccasionStyle: Codable, Equatable {
        let background: Background?
        let subtitleColor: String?
        let badge: BadgeStyle?

        private enum CodingKeys: String, CodingKey { case background, subtitleColor, badge }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let current = try values.decodeIfPresent(Background.self, forKey: .background) {
                background = current
            } else {
                // Earlier themes stored the background directly in the occasion entry.
                let legacy = try Background(from: decoder)
                background = legacy.color == nil && legacy.painter == nil ? nil : legacy
            }
            subtitleColor = try values.decodeIfPresent(String.self, forKey: .subtitleColor)
            badge = try values.decodeIfPresent(BadgeStyle.self, forKey: .badge)
        }
    }

    struct ScheduleRule: Codable, Equatable {
        struct RowStyle: Codable, Equatable {
            let titleColor: String?
            let icon: String?
        }

        struct Match: Codable, Equatable {
            let id: UUID?
            let titleEquals: String?
            let titleContains: String?

            var key: String {
                if let id { return "id:" + id.uuidString.lowercased() }
                if let titleEquals { return "titleEquals:" + titleEquals.precomposedStringWithCanonicalMapping }
                return "titleContains:" + (titleContains ?? "").precomposedStringWithCanonicalMapping
            }

            func matches(_ schedule: CalendarSchedule) -> Bool {
                if let id { return schedule.id == id }
                if let titleEquals { return schedule.title == titleEquals }
                if let titleContains { return schedule.title.contains(titleContains) }
                return false
            }
        }

        let match: Match
        var background: Background?
        let dotColor: String?
        let row: RowStyle?
    }

    let festivals: [String: OccasionStyle]
    let solarTerms: [String: OccasionStyle]
    let schedules: [ScheduleRule]

    var symbolNames: Set<String> {
        Set(festivals.values.compactMap { $0.badge?.icon } +
            solarTerms.values.compactMap { $0.badge?.icon } +
            schedules.compactMap { $0.row?.icon })
    }

    var identifiedSchedules: [(id: String, rule: ScheduleRule)] {
        var occurrences: [String: Int] = [:]
        return schedules.map { rule in
            let key = rule.match.key
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            return ("schedule." + key + "#" + String(occurrence), rule)
        }
    }

    func withStableSchedulePainters(appearance: String) -> Self {
        let updated = identifiedSchedules.map { id, rule in
            guard rule.background?.painter != nil else { return rule }
            var updatedRule = rule
            updatedRule.background = Background(color: nil, painter: appearance + "." + id)
            return updatedRule
        }
        return Self(festivals: festivals, solarTerms: solarTerms, schedules: updated)
    }

    static let civilFestivals = [
        (id: "newYearsDay", name: "元旦", month: 1, day: 1),
        (id: "laborDay", name: "劳动节", month: 5, day: 1),
        (id: "nationalDay", name: "国庆节", month: 10, day: 1)
    ]
    static let festivalNames = Dictionary(uniqueKeysWithValues:
        Festival.allCases.map { ($0.rawValue, $0.name) } + civilFestivals.map { ($0.id, $0.name) }
    )
    static let solarTermNames = [
        "minorCold": "小寒", "majorCold": "大寒", "startOfSpring": "立春", "rainWater": "雨水",
        "awakeningOfInsects": "惊蛰", "springEquinox": "春分", "qingming": "清明", "grainRain": "谷雨",
        "startOfSummer": "立夏", "grainFull": "小满", "grainInEar": "芒种", "summerSolstice": "夏至",
        "minorHeat": "小暑", "majorHeat": "大暑", "startOfAutumn": "立秋", "endOfHeat": "处暑",
        "whiteDew": "白露", "autumnEquinox": "秋分", "coldDew": "寒露", "frostDescent": "霜降",
        "startOfWinter": "立冬", "xiaoxue": "小雪", "majorSnow": "大雪", "winterSolstice": "冬至"
    ]
    private static let solarTermIDs = Dictionary(uniqueKeysWithValues: solarTermNames.map { ($0.value, $0.key) })

    private func civilFestival(on day: CalendarDay) -> (id: String, name: String, month: Int, day: Int)? {
        Self.civilFestivals.first { $0.month == day.month && $0.day == day.day }
    }

    func festivalStyles(for day: CalendarDay, festival: Festival?) -> [String: OccasionStyle] {
        var result: [String: OccasionStyle] = [:]
        if let festival { result[festival.name] = festivals[festival.rawValue] }
        if let civil = civilFestival(on: day) { result[civil.name] = festivals[civil.id] }
        return result
    }

    func solarTermStyle(named name: String?) -> OccasionStyle? {
        guard let name, let id = Self.solarTermIDs[name] else { return nil }
        return solarTerms[id]
    }

    func scheduleRule(for schedule: CalendarSchedule) -> ScheduleRule? {
        schedules.first { $0.match.matches(schedule) }
    }

    private func occasionBackgrounds(for day: CalendarDay, festival: Festival?, solarTerm: String?) -> [Background] {
        let traditional = festival.flatMap { festivals[$0.rawValue]?.background }
        let civil = civilFestival(on: day).flatMap { festivals[$0.id]?.background }
        let term = solarTermStyle(named: solarTerm)?.background
        return [traditional, civil, term].compactMap { $0 }
    }

    func occasionPainter(for day: CalendarDay, solarTerm: String?) -> String? {
        occasionBackgrounds(for: day, festival: day.festival(solarTerm: solarTerm), solarTerm: solarTerm)
            .compactMap(\.painter).first
    }

    func background(for day: CalendarDay, festival: Festival?, solarTerm: String?,
                    schedules daySchedules: [CalendarSchedule]) -> Background? {
        if let background = occasionBackgrounds(for: day, festival: festival, solarTerm: solarTerm).first {
            return background
        }
        for schedule in daySchedules {
            if let background = scheduleRule(for: schedule)?.background { return background }
        }
        return nil
    }
}

extension Color {
    init?(themeHex: String?) {
        guard let themeHex, themeHex.count == 7, themeHex.first == "#",
              let rgb = UInt32(themeHex.dropFirst(), radix: 16) else { return nil }
        self.init(hex: rgb)
    }
}

struct CalendarThemeTile: Equatable, Encodable {
    struct Key: Hashable {
        let id: String
        let painter: String
    }

    let id: String
    let painter: String
    let frame: CGRect

    var key: Key { Key(id: id, painter: painter) }

    private enum CodingKeys: String, CodingKey { case id, painter, x, y, width, height }

    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(id, forKey: .id)
        try fields.encode(painter, forKey: .painter)
        try fields.encode(frame.minX, forKey: .x)
        try fields.encode(frame.minY, forKey: .y)
        try fields.encode(frame.width, forKey: .width)
        try fields.encode(frame.height, forKey: .height)
    }
}

struct CalendarThemeCanvas: NSViewRepresentable {
    private final class ThemeWebView: WKWebView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    struct Scene: Equatable, Encodable {
        let tiles: [CalendarThemeTile]
        let isDark: Bool
        let reduceMotion: Bool
        var previewTileID: String? = nil
    }

    enum Request: Equatable {
        case validate(String)
        case draw(CalendarCustomTheme, Scene)

        var source: String {
            switch self {
            case .validate(let source): return source
            case .draw(let theme, _): return theme.source
            }
        }
    }

    let request: Request
    var onValidation: ((CalendarThemeAppearances) -> Void)? = nil
    var onFailure: ((String) -> Void)? = nil
    var onDrawingError: ((CalendarThemeTile.Key, String) -> Void)? = nil
    var onPreviewPassed: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = ThemeWebView(frame: .zero, configuration: configuration)
        view.isHidden = true
        context.coordinator.start(view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(self)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private struct ActiveScene {
            let id = UUID().uuidString
            let request: Request
            let tiles: Set<CalendarThemeTile.Key>
            var previewPassed = false
        }

        private var parent: CalendarThemeCanvas
        private weak var view: WKWebView?
        private var ready = false
        private var allowedInitialNavigation = false
        private var failed = false
        private var busy = false
        private var loadedTheme: CalendarCustomTheme?
        private var displayedRequest: Request?
        private var deadline: Task<Void, Never>?
        private var playbackDeadline: Task<Void, Never>?
        private var activeScene: ActiveScene?

        init(_ parent: CalendarThemeCanvas) {
            self.parent = parent
        }

        func start(_ view: WKWebView) {
            self.view = view
            view.navigationDelegate = self
            guard let url = Bundle.main.url(forResource: "CalendarThemeCanvas", withExtension: "js"),
                  let script = try? String(contentsOf: url, encoding: .utf8) else {
                Task { self.fail("无法读取主题渲染器。") }
                return
            }
            let content = view.configuration.userContentController
            content.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            content.add(ThemeEventHandler(self), contentWorld: .page, name: "calendarThemeEvent")
            setDeadline()
            view.loadHTMLString(Self.page, baseURL: nil)
        }

        func update(_ parent: CalendarThemeCanvas) {
            self.parent = parent
            applyPendingRequest()
        }

        func stop() {
            deadline?.cancel()
            deadline = nil
            playbackDeadline?.cancel()
            playbackDeadline = nil
            activeScene = nil
            failed = true
            view?.configuration.userContentController.removeScriptMessageHandler(forName: "calendarThemeEvent", contentWorld: .page)
            view?.stopLoading()
            view?.navigationDelegate = nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if !allowedInitialNavigation, action.targetFrame?.isMainFrame == true, action.navigationType == .other {
                allowedInitialNavigation = true
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            deadline?.cancel()
            ready = true
            applyPendingRequest()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            fail("主题渲染进程已结束。")
        }

        private func applyPendingRequest() {
            guard ready, !failed, !busy, let view, displayedRequest != parent.request else { return }
            let request = parent.request
            let script: String
            let arguments: [String: Any]
            let loading: Bool
            switch request {
            case .draw(let theme, let scene) where theme == loadedTheme:
                do {
                    let data = try JSONEncoder().encode(scene)
                    let active = ActiveScene(request: request, tiles: Set(scene.tiles.map(\.key)))
                    activeScene = active
                    playbackDeadline?.cancel()
                    script = "calendarThemeCanvas.show(JSON.parse(scene), sceneID); return true;"
                    arguments = ["scene": String(decoding: data, as: UTF8.self), "sceneID": active.id]
                    loading = false
                } catch {
                    fail(error.localizedDescription)
                    return
                }
            default:
                let validating: Bool
                if case .validate = request { validating = true } else { validating = false }
                script = "return calendarThemeCanvas.load(source, validating, festivalIDs, solarTermIDs);"
                arguments = [
                    "source": request.source, "validating": validating,
                    "festivalIDs": CalendarThemeRules.festivalNames.keys.sorted(),
                    "solarTermIDs": CalendarThemeRules.solarTermNames.keys.sorted()
                ]
                loading = true
            }
            busy = true
            setDeadline()
            view.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { [weak self] result in
                self?.finish(request, loading: loading, result: result)
            }
        }

        private func finish(_ request: Request, loading: Bool, result: Result<Any, Error>) {
            guard !failed else { return }
            deadline?.cancel()
            busy = false
            switch result {
            case .success(let value):
                if loading {
                    guard let json = value as? String,
                          let rules = try? JSONDecoder().decode(CalendarThemeAppearances.self, from: Data(json.utf8)) else {
                        fail("无法读取主题规则。")
                        return
                    }
                    switch request {
                    case .validate:
                        let symbols = rules.light.symbolNames.union(rules.dark.symbolNames)
                        if let invalid = symbols.sorted().first(where: {
                            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil
                        }) {
                            fail("找不到系统图标“\(invalid)”。")
                            return
                        }
                        displayedRequest = request
                        if request == parent.request { parent.onValidation?(rules) }
                    case .draw(let theme, _):
                        displayedRequest = nil
                        guard case .draw(let currentTheme, _) = parent.request, currentTheme == theme else {
                            loadedTheme = nil
                            break
                        }
                        guard theme.rules == rules else {
                            fail("绘制时生成的主题规则与已保存的规则不一致，请重新预览并应用。")
                            return
                        }
                        loadedTheme = theme
                    }
                } else {
                    displayedRequest = request
                    if request.source == parent.request.source { view?.isHidden = false }
                    reportPreviewPass()
                }
            case .failure(let error):
                if request.source == parent.request.source {
                    let details = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
                    fail(details ?? error.localizedDescription)
                    return
                }
                loadedTheme = nil
                displayedRequest = nil
            }
            applyPendingRequest()
        }

        private func setDeadline() {
            deadline?.cancel()
            deadline = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
                self?.fail("主题脚本执行超时。")
            }
        }

        private func fail(_ message: String) {
            guard !failed else { return }
            stop()
            view?.isHidden = true
            parent.onFailure?(message)
        }

        private func receive(_ event: [String: Any]) {
            guard !failed, let activeScene, event["sceneID"] as? String == activeScene.id else { return }
            switch event["kind"] as? String {
            case "frame":
                playbackDeadline?.cancel()
                playbackDeadline = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                        guard let self, !Task.isCancelled else { return }
                        if self.view?.window?.occlusionState.contains(.visible) == true {
                            self.fail("主题动画绘制超时。")
                            return
                        }
                    }
                }
            case "idle":
                playbackDeadline?.cancel()
                playbackDeadline = nil
            case "previewPassed":
                guard activeScene.request == parent.request else { return }
                self.activeScene?.previewPassed = true
                reportPreviewPass()
            case "error":
                guard activeScene.request == parent.request, let id = event["tileID"] as? String,
                      let painter = event["painter"] as? String, let message = event["message"] as? String else { return }
                let key = CalendarThemeTile.Key(id: id, painter: painter)
                guard activeScene.tiles.contains(key) else { return }
                parent.onDrawingError?(key, String(message.prefix(500)))
            default:
                break
            }
        }

        private func reportPreviewPass() {
            guard let activeScene, activeScene.previewPassed,
                  activeScene.request == displayedRequest, activeScene.request == parent.request else { return }
            self.activeScene?.previewPassed = false
            parent.onPreviewPassed?()
        }

        @MainActor
        private final class ThemeEventHandler: NSObject, WKScriptMessageHandler {
            weak var coordinator: Coordinator?

            init(_ coordinator: Coordinator) {
                self.coordinator = coordinator
            }

            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                guard message.frameInfo.isMainFrame, let event = message.body as? [String: Any] else { return }
                coordinator?.receive(event)
            }
        }

        private static let page = """
        <!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy"
              content="default-src 'none'; script-src 'unsafe-eval'; style-src 'unsafe-inline'; img-src data: blob:; base-uri 'none'; form-action 'none'">
        <style>
        html,body { margin: 0; overflow: hidden; width: 100%; height: 100%; background: #fff; }
        canvas { display: block; width: 100%; height: 100%; }
        </style></head><body><canvas aria-hidden="true"></canvas></body></html>
        """
    }
}
