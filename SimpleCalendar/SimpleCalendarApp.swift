import AppKit
import SwiftUI

@main
enum SimpleCalendarApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let controller = StatusBarController()
        application.delegate = controller
        withExtendedLifetime(controller) {
            application.run()
        }
    }
}

@MainActor
private final class StatusBarController: NSObject, NSApplicationDelegate {
    private let model = CalendarModel()
    private let settings = CalendarSettings()
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var scheduleWindow: NSWindow?
    private var scheduleEditorDay: Date?
    private var statusItem: NSStatusItem?
    private var clock: Timer?
    private var holidayRefreshTimer: Timer?

    private let clockFormatter = ClockField.makeFormatter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: CalendarPopoverView(
            model: model, settings: settings,
            openSettings: { [weak self] in self?.showSettings() },
            openSchedule: { [weak self] day in self?.showScheduleEditor(for: day) }
        ))
        popover.contentSize = CalendarPopoverView.contentSize
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey(_:)),
                                               name: NSWindow.didResignKeyNotification, object: nil)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "打开 SimpleCalendar，右键查看设置和退出"
        }

        updateClock()
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(clockDidTick(_:)),
                          userInfo: nil, repeats: true)
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        clock = timer

        refreshHolidays()
        let refreshTimer = Timer(timeInterval: 86_400, target: self, selector: #selector(holidayRefreshDidTick(_:)),
                                 userInfo: nil, repeats: true)
        refreshTimer.tolerance = 3_600
        RunLoop.main.add(refreshTimer, forMode: .common)
        holidayRefreshTimer = refreshTimer
    }

    func applicationDidResignActive(_ notification: Notification) {
        if popover.isShown { popover.performClose(nil) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        settings.refreshLoginItemStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        clock?.invalidate()
        clock = nil
        holidayRefreshTimer?.invalidate()
        holidayRefreshTimer = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    @objc private func clockDidTick(_ timer: Timer) {
        updateClock()
    }

    private func updateClock() {
        let now = Date.now
        let title = clockFormatter.menuBarTitle(at: now, pattern: settings.clockPattern)
        if let button = statusItem?.button, button.attributedTitle.string != title {
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
            )
        }
        model.refreshToday(at: now)
    }

    @objc private func holidayRefreshDidTick(_ timer: Timer) {
        refreshHolidays()
    }

    private func refreshHolidays() {
        Task { [settings] in await settings.refreshHolidaysIfNeeded() }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === popover.contentViewController?.view.window else { return }

        // 让 AppKit 完成焦点切换，再关闭仍可见的弹窗。
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, !window.isKeyWindow, self.popover.isShown,
                  window === self.popover.contentViewController?.view.window else { return }
            self.popover.performClose(nil)
        }
    }

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            popover.performClose(sender)
            let menu = NSMenu()
            let settingsItem = menu.addItem(withTitle: "设置…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(.separator())
            let quitItem = menu.addItem(withTitle: "退出 SimpleCalendar",
                                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            quitItem.target = NSApp
            NSMenu.popUpContextMenu(menu, with: event, for: sender)
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            model.goToToday()
            activateApp()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func openSettingsFromMenu(_ sender: NSMenuItem) {
        showSettings()
    }

    private func showSettings() {
        let screenFrame = menuBarScreen?.visibleFrame
        popover.performClose(nil)
        settings.refreshLoginItemStatus()
        let window: NSWindow
        if let settingsWindow {
            window = settingsWindow
        } else {
            let view = SettingsView(settings: settings, model: model) { [weak self] in
                guard let self else { return }
                self.showScheduleEditor(for: self.model.today, relativeTo: self.settingsWindow)
            }
            let controller = NSHostingController(rootView: view)
            window = NSWindow(contentViewController: controller)
            window.title = "SimpleCalendar 设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        if !window.isVisible { center(window, in: screenFrame) }
        activateApp()
        window.makeKeyAndOrderFront(nil)
    }

    private func showScheduleEditor(for day: Date, relativeTo parent: NSWindow? = nil) {
        let referenceFrame = parent?.frame ?? menuBarScreen?.visibleFrame
        popover.performClose(nil)
        activateApp()
        if let scheduleWindow, scheduleWindow.isVisible, scheduleEditorDay == day {
            if parent != nil { center(scheduleWindow, in: referenceFrame) }
            scheduleWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = ScheduleEditorView(model: model, date: model.scheduleDraft(for: day)) { [weak self] in
            self?.scheduleWindow?.close()
        }
        let controller = NSHostingController(rootView: view)
        let window: NSWindow
        if let scheduleWindow {
            window = scheduleWindow
            window.contentViewController = controller
        } else {
            window = NSWindow(contentViewController: controller)
            window.title = "添加日程"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            scheduleWindow = window
        }
        scheduleEditorDay = day
        center(window, in: referenceFrame)
        window.makeKeyAndOrderFront(nil)
    }

    private var menuBarScreen: NSScreen? {
        if popover.isShown, let screen = popover.contentViewController?.view.window?.screen {
            return screen
        }
        return statusItem?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func center(_ window: NSWindow, in referenceFrame: NSRect?) {
        guard let referenceFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: referenceFrame.midX - size.width / 2,
                                      y: referenceFrame.midY - size.height / 2))
    }

    private func activateApp() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
