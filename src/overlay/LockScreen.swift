import Cocoa

// MARK: - Quotes (rotate every 30s on lock screen)

let quotes: [String] = [
    "能按时关掉屏幕的人，不会过得太差",
    "能早睡早起的人，就是世界上最优秀的人",
    "你做到了大多数人做不到的事：关掉电脑",
    "自律的人不是不想玩，是知道什么时候该停",
    "睡饱的人，运气不会太差",
    "明天的你会感谢现在的你",
    "还记得上次早睡早起，精力充沛的自己么",
    "睡一觉，好主意自己会来找你",
    "深度睡眠发生在入睡后的前几个小时，越早睡越赚",
    "睡眠不足时，大脑的决策能力和喝醉差不多",
]

// MARK: - Config

struct SleepConfig {
    let wakeupTime: String
    let bedtime: String
    let activeDays: Set<Int>  // 1=Mon ... 7=Sun

    static func load() -> SleepConfig {
        let configPath = NSHomeDirectory() + "/.timetosleep/config.json"
        var wakeup = "07:00"
        var bedtime = "23:00"
        var days: Set<Int> = [1,2,3,4,5]

        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let w = json["wakeup"] as? String { wakeup = w }
            if let b = json["bedtime"] as? String { bedtime = b }
            if let d = json["days"] as? [Any] {
                days = Set(d.compactMap { item -> Int? in
                    if let s = item as? String { return Int(s) }
                    if let n = item as? Int { return n }
                    return nil
                })
            }
        }
        return SleepConfig(wakeupTime: wakeup, bedtime: bedtime, activeDays: days)
    }
}

// MARK: - Stats

enum DayStatus { case completed, skipped, noData }

struct SleepStats {
    let streak: Int
    let totalCompleted: Int
    let totalNights: Int
    let recentDays: [(String, DayStatus)]

    var rate: Int {
        totalNights > 0 ? Int(Double(totalCompleted) / Double(totalNights) * 100) : 0
    }

    static func load(config: SleepConfig) -> SleepStats {
        let statsPath = NSHomeDirectory() + "/.timetosleep/stats.json"
        var records: [[String: String]] = []

        if let data = try? Data(contentsOf: URL(fileURLWithPath: statsPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let recs = json["records"] as? [[String: String]] {
            records = recs
        }

        let total = records.count
        let completed = records.filter { $0["status"] == "completed" }.count

        let cal = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let statusByDate = Dictionary(uniqueKeysWithValues: records.compactMap { r -> (String, String)? in
            guard let d = r["date"], let s = r["status"] else { return nil }
            return (d, s)
        })

        // Streak: skip inactive days and skipped days
        var streak = 0
        var day = cal.date(byAdding: .day, value: -1, to: Date())!
        for _ in 0..<400 {
            let ds = df.string(from: day)
            let weekday = cal.component(.weekday, from: day)
            // Convert from Apple's 1=Sun..7=Sat to ISO 1=Mon..7=Sun
            let isoWeekday = weekday == 1 ? 7 : weekday - 1

            if !config.activeDays.contains(isoWeekday) {
                day = cal.date(byAdding: .day, value: -1, to: day)!
                continue
            }

            let status = statusByDate[ds] ?? ""
            if status == "completed" {
                streak += 1
                day = cal.date(byAdding: .day, value: -1, to: day)!
            } else if status.hasPrefix("skipped") {
                day = cal.date(byAdding: .day, value: -1, to: day)!
                continue
            } else {
                break
            }
        }

        // Recent 28 days for the grid
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "d"
        var recent: [(String, DayStatus)] = []
        for i in (0...27).reversed() {
            let d = cal.date(byAdding: .day, value: -i, to: Date())!
            let ds = df.string(from: d)
            let label = dayFmt.string(from: d)
            let status: DayStatus
            if let s = statusByDate[ds] {
                status = s == "completed" ? .completed : .skipped
            } else {
                status = .noData
            }
            recent.append((label, status))
        }

        return SleepStats(streak: streak, totalCompleted: completed, totalNights: total, recentDays: recent)
    }
}

// MARK: - Lock Window Controller

class LockWindowController {
    let config: SleepConfig
    let stats: SleepStats
    var windows: [NSWindow] = []
    var clockTimer: Timer?

    init(config: SleepConfig, stats: SleepStats) {
        self.config = config
        self.stats = stats
    }

    func activate() {
        for screen in NSScreen.screens {
            windows.append(createLockWindow(for: screen))
        }
        startClockUpdate()
        setupKeepAlive()
        monitorScreenChanges()
    }

    private func createLockWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.isOpaque = true
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.canHide = false
        window.ignoresMouseEvents = false
        window.setFrame(screen.frame, display: true)

        let localFrame = NSRect(origin: .zero, size: screen.frame.size)
        window.contentView = LockScreenView(frame: localFrame, config: config, stats: stats)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func monitorScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildWindows() }
    }

    private func rebuildWindows() {
        for w in windows { w.close() }
        windows.removeAll()
        for screen in NSScreen.screens { windows.append(createLockWindow(for: screen)) }
    }

    private func startClockUpdate() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClock()
            self?.checkWakeTime()
        }
    }

    private func updateClock() {
        for w in windows { (w.contentView as? LockScreenView)?.updateTime() }
    }

    private func checkWakeTime() {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        if f.string(from: Date()) == config.wakeupTime { exit(0) }
    }

    private func setupKeepAlive() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let screens = NSScreen.screens
            if screens.count != self.windows.count { self.rebuildWindows(); return }
            for (i, w) in self.windows.enumerated() {
                if i < screens.count { w.setFrame(screens[i].frame, display: false) }
                w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
                w.makeKeyAndOrderFront(nil)
            }
        }
    }
}

// MARK: - Streak Grid View

class StreakGridView: NSView {
    let days: [(String, DayStatus)]
    let cols = 7
    let dotSize: CGFloat = 10
    let gap: CGFloat = 6

    init(frame: NSRect, days: [(String, DayStatus)]) {
        self.days = days
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let totalRows = Int(ceil(Double(days.count) / Double(cols)))
        let cellSize = dotSize + gap
        let gridWidth = CGFloat(cols) * cellSize - gap
        let gridHeight = CGFloat(totalRows) * cellSize - gap
        let offsetX = (bounds.width - gridWidth) / 2
        let offsetY = (bounds.height - gridHeight) / 2

        for (index, (_, status)) in days.enumerated() {
            let col = index % cols
            let row = totalRows - 1 - (index / cols)
            let x = offsetX + CGFloat(col) * cellSize
            let y = offsetY + CGFloat(row) * cellSize
            let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)

            let color: CGColor
            switch status {
            case .completed:
                color = NSColor(red: 0.35, green: 0.75, blue: 0.45, alpha: 1.0).cgColor
            case .skipped:
                color = NSColor(white: 0.25, alpha: 1.0).cgColor
            case .noData:
                color = NSColor(white: 0.1, alpha: 1.0).cgColor
            }
            ctx.setFillColor(color)
            ctx.fillEllipse(in: rect)
        }
    }
}

// MARK: - Lock Screen View

class LockScreenView: NSView {
    let config: SleepConfig
    let stats: SleepStats
    private var timeLabel: NSTextField!
    private var quoteLabel: NSTextField!
    private var quoteTimer: Timer?
    private var currentQuoteIndex: Int

    init(frame: NSRect, config: SleepConfig, stats: SleepStats) {
        self.config = config
        self.stats = stats
        self.currentQuoteIndex = Int.random(in: 0..<quotes.count)
        super.init(frame: frame)
        setupUI()
        startQuoteRotation()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true

        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.colors = [
            NSColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 1.0).cgColor,
            NSColor(red: 0.01, green: 0.01, blue: 0.03, alpha: 1.0).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        layer?.addSublayer(gradient)

        let containerHeight: CGFloat = 460
        let container = NSView(frame: NSRect(
            x: bounds.midX - 300, y: bounds.midY - containerHeight / 2,
            width: 600, height: containerHeight
        ))
        container.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        addSubview(container)

        var y: CGFloat = containerHeight

        // Moon
        y -= 50
        container.addSubview(makeLabel(text: "🌙", fontSize: 36, color: .white,
                                        frame: NSRect(x: 0, y: y, width: 600, height: 44)))

        // Time
        y -= 85
        timeLabel = makeLabel(text: currentTimeString(), fontSize: 72, color: .white,
                              frame: NSRect(x: 0, y: y, width: 600, height: 85))
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 72, weight: .ultraLight)
        container.addSubview(timeLabel)

        // Hero stat: streak or total
        y -= 48
        if stats.streak > 0 {
            let heroLabel = makeLabel(
                text: "连续早睡 \(stats.streak) 天",
                fontSize: 28, color: .white,
                frame: NSRect(x: 0, y: y, width: 600, height: 38)
            )
            heroLabel.font = NSFont.systemFont(ofSize: 28, weight: .medium)
            container.addSubview(heroLabel)
        } else if stats.totalCompleted > 0 {
            let heroLabel = makeLabel(
                text: "累计早睡 \(stats.totalCompleted) 天",
                fontSize: 28, color: .white,
                frame: NSRect(x: 0, y: y, width: 600, height: 38)
            )
            heroLabel.font = NSFont.systemFont(ofSize: 28, weight: .medium)
            container.addSubview(heroLabel)
        } else {
            container.addSubview(makeLabel(
                text: "今晚是新的开始",
                fontSize: 20, color: NSColor(white: 0.5, alpha: 1.0),
                frame: NSRect(x: 0, y: y, width: 600, height: 30)
            ))
        }

        // Sub-stat line
        y -= 26
        if stats.streak > 0 && stats.totalCompleted > stats.streak {
            container.addSubview(makeLabel(
                text: "累计早睡 \(stats.totalCompleted) 天 · 守约率 \(stats.rate)%",
                fontSize: 13, color: NSColor(white: 0.4, alpha: 1.0),
                frame: NSRect(x: 0, y: y, width: 600, height: 20)
            ))
        } else if stats.totalNights > 0 {
            container.addSubview(makeLabel(
                text: "守约率 \(stats.rate)%",
                fontSize: 13, color: NSColor(white: 0.4, alpha: 1.0),
                frame: NSRect(x: 0, y: y, width: 600, height: 20)
            ))
        }

        // Streak grid
        y -= 82
        let gridView = StreakGridView(
            frame: NSRect(x: 120, y: y, width: 360, height: 70),
            days: stats.recentDays
        )
        container.addSubview(gridView)

        // Grid legend
        y -= 18
        if stats.totalNights > 0 {
            container.addSubview(makeLabel(
                text: "最近 4 周",
                fontSize: 11, color: NSColor(white: 0.25, alpha: 1.0),
                frame: NSRect(x: 0, y: y, width: 600, height: 16)
            ))
        }

        // Rotating quote
        y -= 40
        quoteLabel = makeLabel(
            text: quotes[currentQuoteIndex],
            fontSize: 15, color: NSColor(white: 0.4, alpha: 1.0),
            frame: NSRect(x: 40, y: y, width: 520, height: 36)
        )
        quoteLabel.font = NSFont.systemFont(ofSize: 15, weight: .light)
        container.addSubview(quoteLabel)

        // Wake time
        y -= 36
        container.addSubview(makeLabel(
            text: "\(config.wakeupTime) 自动解锁",
            fontSize: 12, color: NSColor(white: 0.2, alpha: 1.0),
            frame: NSRect(x: 0, y: y, width: 600, height: 18)
        ))
    }

    private func startQuoteRotation() {
        quoteTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.rotateQuote()
        }
    }

    private func rotateQuote() {
        guard let label = quoteLabel else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.0
            label.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.currentQuoteIndex = (self.currentQuoteIndex + 1) % quotes.count
            label.stringValue = quotes[self.currentQuoteIndex]
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 1.0
                label.animator().alphaValue = 1.0
            })
        })
    }

    private func makeLabel(text: String, fontSize: CGFloat, color: NSColor, frame: NSRect) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.font = NSFont.systemFont(ofSize: fontSize, weight: .light)
        label.textColor = color
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        return label
    }

    func updateTime() { timeLabel?.stringValue = currentTimeString() }

    private func currentTimeString() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}

// MARK: - App Delegate

class LockAppDelegate: NSObject, NSApplicationDelegate {
    var controller: LockWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = SleepConfig.load()
        let stats = SleepStats.load(config: config)
        controller = LockWindowController(config: config, stats: stats)
        controller?.activate()
        NSApp.setActivationPolicy(.prohibited)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { _ in nil }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { _ in nil }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = LockAppDelegate()
app.delegate = delegate
app.run()
