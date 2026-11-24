根据最终选择，V1 的设计方向正式确定：

**SimpleCalendar**

V1 设计基线

# **简约日历，突出重要日期。**

macOS 原生菜单栏日历，以日期阅读为核心，提供中国传统节日、节气、法定节假日和调休信息。

节日视觉

**轻量装饰**

日期详情

**日历下方**

弹窗宽度

**约 380 px**

部署目标

**macOS 13+**

# **一、最终 UI 设计规范**

## **1. 整体布局**

采用一个固定尺寸的 `NSPopover`，不使用独立窗口。

# **2026年11月**

丙午年 · 农历十月

今天

一

二

三

四

五

六

日

## **16**

初七

## **17**

初八

## **18**

初九

## **19**

初十

## **20**

十一

## **21**

十二

## **22**

十三

## **23**

十四

## **24**

十五

## **25**

十六

## **26**

十七

## **27**

十八

## **28**

十九

## **29**

二十

## **30**

廿一

## **01**

廿二

## **02**

廿三

## **03**

廿四

## **04**

廿五

## **05**

廿六

## **06**

廿七

选中日期

# **23**

11月 · 星期一

农历十月十四

工作日

无特殊节日

最终布局示意，非真实日历数据

布局从上到下分为三个区域：

| 区域   | 内容            | 高度参考   |
| ---- | ------------- | ------ |
| 月份导航 | 年月、上月、下月、今天   | 42 px  |
| 月历主体 | 星期标题、42 个日期格  | 295 px |
| 日期详情 | 公历、星期、农历、节日标签 | 95 px  |

整体建议：

- 宽度：380 px。
- 高度：约 468 px。
- 圆角：12 px 左右。
- 日期网格：7 列、固定 6 行。
- 周一作为每周第一天。
- 自动适配 macOS 深色、浅色模式。

固定 6 行可以避免不同月份切换时窗口高度变化。

## **2. 日期单元格规范**

每个日期格只显示两个主要信息：

1. 公历日期。
2. 农历日期或特殊日期名称。

# **18**

初九

普通日期

# **21**

十二

周末

# **23**

十四

今天

# **24**

十五

选中

尺寸规范：

| 元素    | 规格              |
| ----- | --------------- |
| 公历数字  | 18～20 pt，Medium |
| 农历文字  | 10～11 pt        |
| 日期格高度 | 42～45 pt        |
| 日期格间距 | 2～3 pt          |
| 节日名称  | 10～11 pt        |
| 状态角标  | 9 pt            |

**特殊日期的文字优先级：**

- 普通日期：显示农历。
- 传统节日：显示节日名称。
- 节气：显示节气名称。
- 法定假日：显示节日名称，并增加「休」标记。
- 调休工作日：保留农历，增加「班」标记。

如果一天存在多个事件，日期格只展示最重要的一个，其余信息放在下方详情区。

## **3. 节日视觉规范**

轻量装饰，不使用大面积插画，不做节日主题切换。

**传统节日**

红色或金色文字、淡色背景、小型装饰标记。

春节

**二十四节气**

绿色文字，轻量标记，不改变日期主体。

立春

**法定休息日**

红色角标，连续假期使用统一视觉。

休

**调休工作日**

蓝色角标，明确区分普通周末。

班

重要节日采用轻量差异：

- 春节：红色 + 金色。
- 中秋：暖黄色。
- 端午：青绿色。
- 清明：青绿色。
- 其他节日：使用统一的节日强调色。

不需要为每个节日制作专属插画。V1 使用 SF Symbols 和颜色即可。

## **4. 颜色规范**

建议定义语义颜色，不要在业务代码中到处硬编码颜色。

| Token                | 浅色模式      | 用途   |
| -------------------- | --------- | ---- |
| `calendarBackground` | `#F5F6F8` | 主背景  |
| `calendarCell`       | `#FFFFFF` | 日期格  |
| `calendarPrimary`    | `#303640` | 日期数字 |
| `calendarSecondary`  | `#9299A3` | 农历文字 |
| `calendarAccent`     | `#F4BB37` | 今天   |
| `calendarFestival`   | `#C94E43` | 节日   |
| `calendarSolarTerm`  | `#448D65` | 节气   |
| `calendarRest`       | `#D64D4D` | 休假   |
| `calendarWork`       | `#6488B8` | 调休工作 |

深色模式使用对应的深色背景、浅色文字和适当提高饱和度的强调色。

建议通过 Asset Catalog 的 Color Set 配置 Light/Dark 两套颜色。

# **二、交互规范**

V1 不需要复杂交互。

| 操作       | 行为          |
| -------- | ----------- |
| 点击菜单栏    | 打开 / 关闭日历   |
| 点击上个月    | 显示上个月       |
| 点击下个月    | 显示下个月       |
| 点击今天     | 返回当前月份并选中今天 |
| 点击日期     | 更新下方详情      |
| 点击其他月份日期 | 切换月份并选中该日期  |
| 点击弹窗外部   | 关闭弹窗        |
| 切换系统主题   | 自动切换 UI 主题  |

有一个细节值得注意：

**今天和选中日期是两个不同状态。**

例如今天是 23 日，你点击 25 日：

- 23 日仍然保留今天的黄色标记。
- 25 日显示选中边框。
- 下方详情展示 25 日信息。

不能因为选择其他日期就丢失今天的视觉提示。

# **三、SwiftUI 技术实现规划**

这里我建议使用混合架构，而不是完全使用 SwiftUI 的 `MenuBarExtra`。

原因是你需要：

- 自定义菜单栏文字。
- 每秒更新时间。
- 精确控制弹窗尺寸。
- 自定义点击打开、关闭行为。

因此使用 AppKit 管理菜单栏和 Popover，SwiftUI 负责所有内容界面。

## **1. 技术选型**

| 功能         | 技术                               |
| ---------- | -------------------------------- |
| 应用入口       | SwiftUI `App`                    |
| 菜单栏        | AppKit `NSStatusItem`            |
| 弹窗         | AppKit `NSPopover`               |
| SwiftUI 容器 | `NSHostingController`            |
| 日历网格       | SwiftUI `LazyVGrid`              |
| 日期计算       | Foundation `Calendar`            |
| 农历         | `Calendar(identifier: .chinese)` |
| 时间刷新       | Foundation `Timer`               |
| 本地配置       | `UserDefaults`                   |
| 开机启动       | `SMAppService`                   |

最低部署版本建议 macOS 13。

## **2. 项目目录结构**

建议保持简单，不引入 Clean Architecture、复杂 DI 或过度抽象。

```
SimpleCalendar/
├── App/
│   ├── SimpleCalendarApp.swift
│   └── AppDelegate.swift
│
├── MenuBar/
│   ├── StatusBarController.swift
│   └── CalendarPopoverController.swift
│
├── Views/
│   ├── CalendarPopoverView.swift
│   ├── MonthHeaderView.swift
│   ├── WeekdayHeaderView.swift
│   ├── CalendarGridView.swift
│   ├── CalendarDayCell.swift
│   ├── SelectedDateDetailView.swift
│   └── SettingsView.swift
│
├── ViewModels/
│   └── CalendarViewModel.swift
│
├── Models/
│   ├── CalendarDay.swift
│   ├── CalendarEvent.swift
│   ├── LunarDate.swift
│   └── HolidaySchedule.swift
│
├── Services/
│   ├── CalendarService.swift
│   ├── LunarCalendarService.swift
│   ├── FestivalService.swift
│   ├── HolidayService.swift
│   └── StatusBarTimeService.swift
│
├── Resources/
│   └── Holidays/
│       ├── 2026.json
│       └── 2027.json
│
└── Assets.xcassets/
    ├── Colors/
    └── AppIcon.appiconset/
```

## **3. 核心模块职责**

**StatusBarController**

负责：

- 创建 `NSStatusItem`。
- 更新菜单栏日期和时间。
- 处理点击事件。
- 管理 Popover 显示状态。

**CalendarPopoverController**

负责：

- 创建 `NSPopover`。
- 设置固定尺寸。
- 将 `CalendarPopoverView` 放入 `NSHostingController`。
- 管理弹窗生命周期。

**CalendarViewModel**

负责：

- 当前展示月份。
- 当前选中日期。
- 今天日期。
- 日期网格数据。
- 选中日期的详情。

**CalendarService**

负责：

- 公历月份计算。
- 获取月份的 42 个日期格。
- 星期排列。
- 日期比较。
- 月份切换。

**LunarCalendarService**

负责：

- 公历转农历。
- 农历月份和日期。
- 闰月识别。
- 农历日期格式化。

**FestivalService**

负责：

- 传统节日识别。
- 二十四节气识别。
- 节日显示优先级。
- 节日视觉类型。

**HolidayService**

负责：

- 读取年度节假日 JSON。
- 识别法定休息日。
- 识别调休工作日。
- 合并节日和节气信息。

各模块不需要相互持有 UI 对象。

# **四、核心数据模型**

这里建议不要把节日名称直接写进 `CalendarDay`，因为同一天可能同时存在多个事件。

例如清明可能同时具备：

- 传统节日。
- 二十四节气。
- 法定休息日。

建议采用独立事件模型。

```
enum CalendarEventType: String, Codable {
    case traditionalFestival
    case solarTerm
    case publicHoliday
}

enum WorkStatus: String, Codable {
    case rest
    case makeupWork
}

struct CalendarEvent: Codable, Identifiable {
    let id: String
    let name: String
    let type: CalendarEventType
    let displayPriority: Int
}

struct CalendarDayMetadata: Codable {
    let date: String
    let workStatus: WorkStatus?
    let events: [CalendarEvent]
}

struct CalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let lunarDate: LunarDate
    let events: [CalendarEvent]
    let workStatus: WorkStatus?

    var id: Date { date }
}
```

这里有几个设计原则：

1. 一个日期可以有多个节日事件。
2. 节假日和调休状态独立于传统节日。
3. 视觉显示优先级由数据决定，而不是写死在 View 中。
4. 日期计算不应该依赖 UI。
5. 日期数据使用本地时区，不能直接使用 UTC 日期字符串比较。

年度节假日 JSON 建议采用：

```
{
  "year": 2027,
  "region": "CN",
  "days": [
    {
      "date": "2027-01-01",
      "workStatus": "rest",
      "events": [
        {
          "id": "new-year",
          "name": "元旦",
          "type": "publicHoliday",
          "displayPriority": 100
        }
      ]
    }
  ]
}
```

注意：这里只是结构示例，不代表 2027 年实际放假安排。

**节假日数据必须以国务院当年正式公告为准。** 尚未公布的年份不应该自行推测调休安排。

# **五、SwiftUI 核心实现规划**

## **1. CalendarPopoverView**

根视图只负责组合，不承担日期计算。

```
struct CalendarPopoverView: View {
    @StateObject private var viewModel = CalendarViewModel()

    var body: some View {
        VStack(spacing: 10) {
            MonthHeaderView(
                month: viewModel.displayedMonth,
                onPrevious: viewModel.previousMonth,
                onNext: viewModel.nextMonth,
                onToday: viewModel.goToToday
            )

            WeekdayHeaderView()

            CalendarGridView(
                days: viewModel.days,
                onSelect: viewModel.selectDate
            )

            Divider()

            SelectedDateDetailView(
                detail: viewModel.selectedDateDetail
            )
        }
        .padding(12)
        .frame(width: 380, height: 468)
    }
}
```

这里仅展示结构示意，实际实现时需要补全模型类型和初始化逻辑。

## **2. CalendarGridView**

使用 `LazyVGrid`：

```
struct CalendarGridView: View {
    let days: [CalendarDay]
    let onSelect: (Date) -> Void

    private let columns = Array(
        repeating: GridItem(
            .flexible(),
            spacing: 2
        ),
        count: 7
    )

    var body: some View {
        LazyVGrid(
            columns: columns,
            spacing: 3
        ) {
            ForEach(days) { day in
                CalendarDayCell(
                    day: day,
                    action: {
                        onSelect(day.date)
                    }
                )
            }
        }
    }
}
```

`CalendarDayCell` 只负责显示，不负责判断节日、农历或法定假日。

这样后期修改视觉样式不会影响日期逻辑。

## **3. CalendarDayCell**

建议将日期样式判断集中在一个地方。

例如：

```
struct CalendarDayStyle {
    let backgroundColor: Color
    let textColor: Color
    let subtitleColor: Color
    let borderColor: Color
}
```

由独立的样式计算方法根据以下状态生成：

- 是否今天。
- 是否选中。
- 是否周末。
- 是否法定休息日。
- 是否调休工作日。
- 是否传统节日。
- 是否节气。

不要在 SwiftUI 的 `body` 中堆叠大量条件表达式。

## **4. StatusBarController**

菜单栏显示建议默认：

```
11月23日 周一 15:34:28
```

实现逻辑：

1. 创建 `NSStatusItem`。
2. 设置 `button.title`。
3. 创建每秒触发的 Timer。
4. 更新状态栏文字。
5. 点击时显示或关闭 Popover。

使用 `NSStatusItem.variableLength`，根据日期格式自动调整宽度。

时间格式可以通过设置进行自定义，例如：

```
M月d日 EEE HH:mm:ss
yyyy-MM-dd HH:mm
HH:mm:ss
M月d日 EEE
```

另外，Timer 应当有明确的生命周期管理，在控制器销毁时失效，避免重复创建。

# **六、日期计算与节假日实现策略**

这是整个项目最容易出现隐性 Bug 的部分。

我建议分开处理：

| 功能    | 实现方案                             |
| ----- | -------------------------------- |
| 公历日期  | Foundation Gregorian Calendar    |
| 农历日期  | Foundation Chinese Calendar      |
| 闰月    | Chinese Calendar 的 `isLeapMonth` |
| 传统节日  | 农历规则                             |
| 二十四节气 | 独立节气算法或经过验证的本地数据                 |
| 法定节假日 | 年度 JSON                          |
| 调休工作日 | 年度 JSON                          |

有几个必须处理的边界情况：

- 农历闰月。
- 春节跨公历年份。
- 清明节同时属于传统节日和节气。
- 法定假期与周末重叠。
- 周末调休上班。
- 系统时区变化。
- 夏令时切换。

尤其是周末调休：

**普通周末默认红色，但如果被标记为调休工作日，就应该显示「班」，不能继续按普通休息日处理。**

节假日状态应该优先于星期本身。

# **七、测试规范**

V1 不应该只测试界面是否能显示，还要测试日期数据是否准确。

建议至少覆盖以下场景：

| 测试   | 验证内容          |
| ---- | ------------- |
| 普通月份 | 42 个日期格正常生成   |
| 跨年月份 | 12 月切换到次年 1 月 |
| 闰年   | 2 月 29 日      |
| 农历闰月 | 闰月识别正确        |
| 春节   | 农历日期和节日名称正确   |
| 清明   | 节日和节气可以同时存在   |
| 国庆假期 | 连续休息日期正确      |
| 调休周末 | 显示「班」         |
| 今天   | 今天与选中状态互不覆盖   |
| 时区变化 | 日期不发生意外偏移     |
| 深色模式 | 颜色对比度正常       |

建议为 `CalendarService`、`LunarCalendarService`、`HolidayService` 编写独立单元测试。

# **八、开发里程碑**

我建议分成四个阶段，不要一次性让 Codex 完成全部内容。

1. **阶段 1：应用基础框架**

   优先实现
   - 创建 macOS App。
   - 菜单栏日期时间。
   - 点击弹出 Popover。
   - 固定尺寸和主题适配。
   - 完成基础月历网格。

   预计 1～2 天
2. **阶段 2：日期信息**
   - 公历日期计算。
   - 农历转换。
   - 日期选择。
   - 下方日期详情。
   - 今天、周末、选中状态。

   预计 1～2 天
3. **阶段 3：节日系统**
   - 传统节日。
   - 二十四节气。
   - 年度法定节假日。
   - 调休工作日。
   - 节日视觉效果。

   预计 2～3 天，节假日数据需单独校验
4. **阶段 4：设置和稳定性**
   - 时间格式设置。
   - 深色和浅色主题。
   - 开机启动。
   - 边界日期测试。
   - 签名和安装包。

   预计 1～2 天

按个人开发、使用 Codex 辅助的估算，约 5～9 个工作日可以完成一个比较完整的 V1。实际取决于节假日数据和 UI 打磨情况。

# **九、最终 V1 范围冻结**

为了防止开发过程中不断增加功能，建议明确暂不开发：

- 天气。
- 提醒事项。
- 待办管理。
- 云同步。
- 用户账号。
- 多日历管理。
- 复杂的节日动画。
- 独立的大型日历窗口。

**V1 最终交付目标**

范围已确定

一款稳定运行于 macOS 的轻量日历：

1. 菜单栏显示日期、星期和实时秒钟。
2. 点击后展示清晰的月历。
3. 公历、农历双层显示。
4. 今天、周末、节日、节气有明确视觉区别。
5. 中国法定节假日和调休准确标注。
6. 点击日期后，下方显示完整日期信息。
7. 深色、浅色模式自动适配。
8. 所有核心功能本地运行，不依赖服务器。

## **十、实际开发时的一个建议**

不要让 Codex 一开始就生成全部代码。

建议先让它完成：

1. Xcode 项目结构。
2. AppKit 菜单栏和 Popover。
3. SwiftUI 月历布局。
4. 日期选择和详情区域。

等 UI 和交互稳定，再接入农历和节日数据。

这样可以避免日期计算、UI 和节假日数据三个问题同时出现，导致难以定位 Bug。

**下一步最合适的是建立项目初始化规范和分阶段开发任务清单**，然后让 Codex 按阶段实现。这样这份设计规范就能直接转化为实际代码，而不会在开发过程中偏离当前确定的 UI 方向。