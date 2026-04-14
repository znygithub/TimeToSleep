import Cocoa

// MARK: - Config

struct SleepConfig {
    let message: String
    let wakeupTime: String
    let bedtime: String

    static func load() -> SleepConfig {
        let configPath = NSHomeDirectory() + "/.timetosleep/config.json"
        var message = "你是一个守承诺的人，说好了早睡就早睡。"
        var wakeup = "07:00"
        var bedtime = "23:00"

        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let m = json["message"] as? String { message = m }
            if let w = json["wakeup"] as? String { wakeup = w }
            if let b = json["bedtime"] as? String { bedtime = b }
        }
        return SleepConfig(message: message, wakeupTime: wakeup, bedtime: bedtime)
    }
}

// MARK: - Stats

enum DayStatus { case completed, skipped, noData }

struct SleepStats {
    let streak: Int
    let totalCompleted: Int
    let totalNights: Int
    let recentDays: [(String, DayStatus)]  // last 28 days, label + status

    var rate: Int {
        totalNights > 0 ? Int(Double(totalCompleted) / Double(totalNights) * 100) : 0
    }

    var streakMessage: String {
        switch streak {
        case 0:     return "今晚是新的开始"
        case 1...6: return "继续保持"
        case 7...13: return "超过一周了！"
        case 14...29: return "习惯正在养成"
        case 30...99: return "一个月了，了不起"
        default:     return "你已经是早睡大师了"
        }
    }

    static func load() -> SleepStats {
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

        // Streak
        var streak = 0
        var day = cal.date(byAdding: .day, value: -1, to: Date())!
        while true {
            let ds = df.string(from: day)
            if statusByDate[ds] == "completed" {
                streak += 1
                day = cal.date(byAdding: .day, value: -1, to: day)!
            } else { break }
        }

        // Recent 28 days for the grid (from 27 days ago to today)
        let dayOfWeekFmt = DateFormatter()
        dayOfWeekFmt.dateFormat = "d"
        var recent: [(String, DayStatus)] = []
        for i in (0...27).reversed() {
            let d = cal.date(byAdding: .day, value: -i, to: Date())!
            let ds = df.string(from: d)
            let label = dayOfWeekFmt.string(from: d)
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

// MARK: - Streak Grid View (the contribution-graph-style calendar)

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

        let totalCols = cols
        let totalRows = Int(ceil(Double(days.count) / Double(totalCols)))
        let cellSize = dotSize + gap

        let gridWidth = CGFloat(totalCols) * cellSize - gap
        let gridHeight = CGFloat(totalRows) * cellSize - gap
        let offsetX = (bounds.width - gridWidth) / 2
        let offsetY = (bounds.height - gridHeight) / 2

        for (index, (_, status)) in days.enumerated() {
            let col = index % totalCols
            let row = totalRows - 1 - (index / totalCols)

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

    init(frame: NSRect, config: SleepConfig, stats: SleepStats) {
        self.config = config
        self.stats = stats
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true

        // Subtle gradient background: very dark blue-black → pure black
        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.colors = [
            NSColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 1.0).cgColor,
            NSColor(red: 0.01, green: 0.01, blue: 0.03, alpha: 1.0).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        layer?.addSublayer(gradient)

        let containerHeight: CGFloat = 480
        let container = NSView(frame: NSRect(
            x: bounds.midX - 300, y: bounds.midY - containerHeight / 2,
            width: 600, height: containerHeight
        ))
        container.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        addSubview(container)

        var y: CGFloat = containerHeight

        // ── Moon ──
        y -= 50
        container.addSubview(makeLabel(text: "🌙", fontSize: 36, color: .white,
                                        frame: NSRect(x: 0, y: y, width: 600, height: 44)))

        // ── Time ──
        y -= 85
        timeLabel = makeLabel(text: currentTimeString(), fontSize: 72, color: .white,
                              frame: NSRect(x: 0, y: y, width: 600, height: 85))
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 72, weight: .ultraLight)
        container.addSubview(timeLabel)

        // ── Streak number (hero) ──
        y -= 48
        if stats.streak > 0 {
            let streakLabel = makeLabel(
                text: "🔥 \(stats.streak)",
                fontSize: 36, color: .white,
                frame: NSRect(x: 0, y: y, width: 600, height: 44)
            )
            streakLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 36, weight: .medium)
            container.addSubview(streakLabel)

            y -= 24
            container.addSubview(makeLabel(
                text: "连续早睡 \(stats.streak) 天 · \(stats.streakMessage)",
                fontSize: 13, color: NSColor(white: 0.45, alpha: 1.0),
                frame: NSRect(x: 0, y: y, width: 600, height: 20)
            ))
        } else {
            container.addSubview(makeLabel(
                text: "今晚是新的开始",
                fontSize: 18, color: NSColor(white: 0.5, alpha: 1.0),
                frame: NSRect(x: 0, y: y, width: 600, height: 28)
            ))
            y -= 10
        }

        // ── Streak grid (last 28 days) ──
        y -= 86
        let gridHeight: CGFloat = 70
        let gridView = StreakGridView(
            frame: NSRect(x: 120, y: y, width: 360, height: gridHeight),
            days: stats.recentDays
        )
        container.addSubview(gridView)

        // ── Grid legend ──
        y -= 18
        if stats.totalNights > 0 {
            container.addSubview(makeLabel(
                text: "最近 4 周 · 累计守约 \(stats.totalCompleted) 晚 · 守约率 \(stats.rate)%",
                fontSize: 11, color: NSColor(white: 0.3, alpha: 1.0),
                frame: NSRect(x: 0, y: y, width: 600, height: 16)
            ))
        }

        // ── Commitment message ──
        y -= 36
        let msgLabel = makeLabel(
            text: "「\(config.message)」",
            fontSize: 16, color: NSColor(white: 0.45, alpha: 1.0),
            frame: NSRect(x: 40, y: y, width: 520, height: 40)
        )
        msgLabel.font = NSFont.systemFont(ofSize: 16, weight: .light)
        container.addSubview(msgLabel)

        // ── Wake time ──
        y -= 32
        container.addSubview(makeLabel(
            text: "\(config.wakeupTime) 自动解锁",
            fontSize: 12, color: NSColor(white: 0.25, alpha: 1.0),
            frame: NSRect(x: 0, y: y, width: 600, height: 18)
        ))

        // ── Breathing hint ──
        y -= 28
        let breatheLabel = makeLabel(
            text: "闭上眼睛，深呼吸，放下今天的一切",
            fontSize: 12, color: NSColor(white: 0.15, alpha: 1.0),
            frame: NSRect(x: 0, y: y, width: 600, height: 18)
        )
        container.addSubview(breatheLabel)
        addBreathingAnimation(to: breatheLabel)
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

    private func addBreathingAnimation(to view: NSView) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0.2
        anim.toValue = 0.8
        anim.duration = 4.0
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(anim, forKey: "breathe")
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
        let stats = SleepStats.load()
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
