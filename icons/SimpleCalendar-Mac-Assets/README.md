# SimpleCalendar macOS 图标资源

本资源包包含应用图标、菜单栏模板图标及原始生成图。

## 目录

- `Assets.xcassets/AppIcon.appiconset/`：Xcode macOS App Icon 完整图标集（16pt 至 512pt，含 1x/2x）。
- `Assets.xcassets/MenuBarIcon.imageset/`：菜单栏模板图标（18pt / 36px Retina）。
- `AppIcon-1024.png`：1024×1024 主图标，可用于预览或其他工具。
- `Source/`：保留的原始生成图片，方便后续修改。
- `Preview/`：图标预览图。

## 在 Xcode 中使用

1. 将 `Assets.xcassets/AppIcon.appiconset` 复制到项目现有的 `Assets.xcassets/` 中。
2. 在 Xcode 的 Target → General → App Icons and Launch Screen → App Icon 中选择 `AppIcon`。
3. 将 `Assets.xcassets/MenuBarIcon.imageset` 也复制到项目的 `Assets.xcassets/` 中。
4. 菜单栏代码可通过 `NSImage(named: "MenuBarIcon")` 加载模板图标。

示例：

```swift
if let image = NSImage(named: "MenuBarIcon") {
    image.isTemplate = true
    image.size = NSSize(width: 18, height: 18)
    statusItem.button?.image = image
}
```

## 注意

- `MenuBarIcon` 是单色模板图标，macOS 会根据菜单栏外观自动渲染前景色。
- AppIcon 使用透明外角；macOS 会在应用图标展示时应用系统圆角遮罩。
- 若项目已有 `AppIcon.appiconset`，请先备份，再合并或替换。
