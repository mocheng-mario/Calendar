import AppKit
import SwiftUI

@main
enum SimpleCalendarApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let controller = StatusBarController()
        application.delegate = controller
        application.mainMenu = makeMainMenu(application)
        withExtendedLifetime(controller) {
            application.run()
        }
    }

    @MainActor
    private static func makeMainMenu(_ application: NSApplication) -> NSMenu {
        let mainMenu = NSMenu()
        let appMenu = NSMenu(title: "Calendar")
        let quit = appMenu.addItem(withTitle: "退出 Calendar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = application
        mainMenu.addItem(withTitle: "Calendar", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(withTitle: "编辑", action: nil, keyEquivalent: "").submenu = edit
        return mainMenu
    }
}

@MainActor
private final class StatusBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = CalendarModel()
    private let settings = CalendarSettings()
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var scheduleWindow: NSWindow?
    private var scheduleEditorDay: Date?
    private var statusItem: NSStatusItem?
    private var clock: Timer?
    private var holidayRefreshTimer: Timer?

    private let clockFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private let menuBarIcon = NSImage(named: "MenuBarIcon")
    private var lastClockItems: [ClockDisplayItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey(_:)),
                                               name: NSWindow.didResignKeyNotification, object: nil)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "打开 Calendar，右键查看设置和退出"
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

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
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
        let items = settings.clockItems(at: now)
        if let button = statusItem?.button, items != lastClockItems {
            lastClockItems = items
            if let menuBarIcon, items.contains(.icon) {
                button.attributedTitle = NSAttributedString(string: "")
                button.image = clockImage(items, icon: menuBarIcon)
                button.imagePosition = .imageOnly
            } else {
                let title = items.compactMap { item -> String? in
                    if case .text(let text) = item { return text }
                    return nil
                }.joined(separator: " ")
                button.image = nil
                button.imagePosition = .noImage
                button.attributedTitle = NSAttributedString(string: title.isEmpty ? "日历" : title, attributes: [.font: clockFont])
            }
            button.setAccessibilityLabel(items.map { item in
                switch item {
                case .icon: return "日历"
                case .text(let text): return text
                }
            }.joined(separator: " "))
        }
        model.refreshToday(at: now)
    }

    private func clockImage(_ items: [ClockDisplayItem], icon: NSImage) -> NSImage {
        let parts = items.map { item -> (size: NSSize, draw: (NSRect) -> Void) in
            switch item {
            case .icon:
                return (icon.size, { icon.draw(in: $0) })
            case .text(let text):
                let title = NSAttributedString(string: text, attributes: [.font: clockFont, .foregroundColor: NSColor.black])
                let size = title.size()
                return (NSSize(width: ceil(size.width), height: ceil(size.height)), { title.draw(in: $0) })
            }
        }
        let gap: CGFloat = 4
        let width = parts.reduce(0) { $0 + $1.size.width } + CGFloat(parts.count - 1) * gap
        let height = parts.map { $0.size.height }.max() ?? icon.size.height
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            var x = rect.minX
            for part in parts {
                part.draw(NSRect(x: x, y: rect.midY - part.size.height / 2, width: part.size.width, height: part.size.height))
                x += part.size.width + gap
            }
            return true
        }
        // Let the status bar tint the entire image, including an icon positioned between text fields.
        image.isTemplate = true
        return image
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
            let quitItem = menu.addItem(withTitle: "退出 Calendar",
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
            configurePopover(on: sender.window?.screen ?? NSScreen.main)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func configurePopover(on screen: NSScreen?) {
        let available = screen.map { CGSize(width: $0.visibleFrame.width - 16, height: $0.visibleFrame.height - 24) }
        let view = CalendarPopoverView(
            model: model, settings: settings, availableSize: available,
            openSettings: { [weak self] in self?.showSettings() },
            openSchedule: { [weak self] day in self?.showScheduleEditor(for: day) },
            resize: { [weak self] size in
                guard let popover = self?.popover else { return }
                let animates = popover.animates
                popover.animates = false
                popover.contentSize = size
                popover.animates = animates
            }
        )
        popover.contentViewController = NSHostingController(rootView: view)
        popover.contentSize = settings.popoverLayout.fitted(in: available).size
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
            window.title = "Calendar 设置"
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
