import Cocoa

// MARK: - Daily quotes (one per day, not rotating)

let quotes: [String] = [
    "能按时关掉屏幕的人，不会过得太差",
    "能早睡早起的人，\n就是世界上最优秀的人",
    "你做到了大多数人做不到的事：\n关掉电脑",
    "自律的人不是不想玩，\n是知道什么时候该停",
    "睡饱的人，运气不会太差",
    "明天的你会感谢现在的你",
    "还记得上次早睡早起，\n精力充沛的自己么",
    "睡一觉，好主意自己会来找你",
    "深度睡眠发生在入睡后的前几个小时，\n越早睡越赚",
    "睡眠不足时，\n大脑的决策能力和喝醉差不多",
]

func todayQuote() -> String {
    let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
    return quotes[day % quotes.count]
}

// MARK: - Config

struct SleepConfig {
    let wakeupTime: String
    let bedtime: String
    let activeDays: Set<Int>

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

struct SleepStats {
    let streak: Int
    let totalCompleted: Int

    static func load(config: SleepConfig) -> SleepStats {
        let statsPath = NSHomeDirectory() + "/.timetosleep/stats.json"
        var records: [[String: String]] = []

        if let data = try? Data(contentsOf: URL(fileURLWithPath: statsPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let recs = json["records"] as? [[String: String]] {
            records = recs
        }

        let completed = records.filter { $0["status"] == "completed" }.count

        let cal = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let statusByDate = Dictionary(uniqueKeysWithValues: records.compactMap { r -> (String, String)? in
            guard let d = r["date"], let s = r["status"] else { return nil }
            return (d, s)
        })

        var streak = 0
        var day = cal.date(byAdding: .day, value: -1, to: Date())!
        for _ in 0..<400 {
            let ds = df.string(from: day)
            let weekday = cal.component(.weekday, from: day)
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

        return SleepStats(streak: streak, totalCompleted: completed)
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

// MARK: - Lock Screen View

class LockScreenView: NSView {
    let config: SleepConfig
    let stats: SleepStats
    private var timeLabel: NSTextField!

    init(frame: NSRect, config: SleepConfig, stats: SleepStats) {
        self.config = config
        self.stats = stats
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true

        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.colors = [
            NSColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1.0).cgColor,
            NSColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1.0).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        layer?.addSublayer(gradient)

        // ── Center content ──

        let containerHeight: CGFloat = 320
        let container = NSView(frame: NSRect(
            x: bounds.midX - 300, y: bounds.midY - containerHeight / 2 + 30,
            width: 600, height: containerHeight
        ))
        container.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        addSubview(container)

        var y: CGFloat = containerHeight

        // Time
        y -= 100
        timeLabel = makeLabel(text: currentTimeString(), fontSize: 80, color: .white,
                              frame: NSRect(x: 0, y: y, width: 600, height: 100))
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 80, weight: .thin)
        container.addSubview(timeLabel)

        // Streak or total
        y -= 36
        let statText: String
        if stats.streak > 0 {
            statText = "🔥 连续早睡第 \(stats.streak) 天"
        } else if stats.totalCompleted > 0 {
            statText = "累计早睡 \(stats.totalCompleted) 天"
        } else {
            statText = "今晚是新的开始"
        }
        container.addSubview(makeLabel(
            text: statText, fontSize: 14,
            color: NSColor(white: 0.5, alpha: 1.0),
            frame: NSRect(x: 0, y: y, width: 600, height: 22)
        ))

        // Quote
        y -= 70
        let quoteLabel = makeLabel(
            text: "「\(todayQuote())」",
            fontSize: 18,
            color: NSColor(white: 0.55, alpha: 1.0),
            frame: NSRect(x: 40, y: y, width: 520, height: 60)
        )
        quoteLabel.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        quoteLabel.maximumNumberOfLines = 3
        container.addSubview(quoteLabel)

        // ── Bottom: wake time ──

        let bottomLabel = makeLabel(
            text: "明早 \(config.wakeupTime) 自动解锁",
            fontSize: 13,
            color: NSColor(white: 0.25, alpha: 1.0),
            frame: NSRect(x: 0, y: 40, width: bounds.width, height: 20)
        )
        bottomLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(bottomLabel)
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
