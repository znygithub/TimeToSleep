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

struct SleepStats {
    let streak: Int
    let totalCompleted: Int
    let totalNights: Int
    let streakMessage: String

    var rate: Int {
        totalNights > 0 ? Int(Double(totalCompleted) / Double(totalNights) * 100) : 0
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

        // Calculate streak: consecutive "completed" days counting backwards from yesterday
        let cal = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let statusByDate = Dictionary(uniqueKeysWithValues: records.compactMap { r -> (String, String)? in
            guard let d = r["date"], let s = r["status"] else { return nil }
            return (d, s)
        })

        var streak = 0
        var day = cal.date(byAdding: .day, value: -1, to: Date())!
        while true {
            let ds = df.string(from: day)
            if statusByDate[ds] == "completed" {
                streak += 1
                day = cal.date(byAdding: .day, value: -1, to: day)!
            } else {
                break
            }
        }

        let msg: String
        switch streak {
        case 0:
            msg = "今晚是新的开始"
        case 1...6:
            msg = "连续早睡 \(streak) 天，继续保持"
        case 7...13:
            msg = "连续早睡 \(streak) 天，超过一周了！"
        case 14...29:
            msg = "连续早睡 \(streak) 天，习惯正在养成"
        case 30...99:
            msg = "连续早睡 \(streak) 天，一个月了，了不起"
        default:
            msg = "连续早睡 \(streak) 天，你已经是早睡大师了"
        }

        return SleepStats(streak: streak, totalCompleted: completed, totalNights: total, streakMessage: msg)
    }
}

// MARK: - Lock Window

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
            let window = createLockWindow(for: screen)
            windows.append(window)
        }
        startClockUpdate()
        setupKeepAlive()
        monitorScreenChanges()
    }

    private func createLockWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.isOpaque = true
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.canHide = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = false

        window.setFrame(screen.frame, display: true)

        let localFrame = NSRect(origin: .zero, size: screen.frame.size)
        let contentView = LockScreenView(frame: localFrame, config: config, stats: stats)
        window.contentView = contentView

        window.makeKeyAndOrderFront(nil)

        return window
    }

    private func monitorScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildWindows()
        }
    }

    private func rebuildWindows() {
        for window in windows { window.close() }
        windows.removeAll()
        for screen in NSScreen.screens {
            let window = createLockWindow(for: screen)
            windows.append(window)
        }
    }

    private func startClockUpdate() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClock()
            self?.checkWakeTime()
        }
    }

    private func updateClock() {
        for window in windows {
            if let view = window.contentView as? LockScreenView {
                view.updateTime()
            }
        }
    }

    private func checkWakeTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let now = formatter.string(from: Date())
        if now == config.wakeupTime {
            exit(0)
        }
    }

    private func setupKeepAlive() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let screens = NSScreen.screens
            if screens.count != self.windows.count {
                self.rebuildWindows()
                return
            }
            for (i, window) in self.windows.enumerated() {
                if i < screens.count {
                    window.setFrame(screens[i].frame, display: false)
                }
                window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
                window.makeKeyAndOrderFront(nil)
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
        layer?.backgroundColor = NSColor.black.cgColor

        let containerHeight: CGFloat = 420
        let container = NSView(frame: NSRect(
            x: bounds.midX - 300,
            y: bounds.midY - containerHeight / 2,
            width: 600,
            height: containerHeight
        ))
        container.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        addSubview(container)

        var y: CGFloat = containerHeight - 60

        // Moon
        let moonLabel = makeLabel(text: "🌙", fontSize: 48, color: .white,
                                  frame: NSRect(x: 0, y: y, width: 600, height: 60))
        container.addSubview(moonLabel)
        y -= 90

        // Time
        timeLabel = makeLabel(text: currentTimeString(), fontSize: 72, color: .white,
                              frame: NSRect(x: 0, y: y, width: 600, height: 90))
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 72, weight: .ultraLight)
        container.addSubview(timeLabel)
        y -= 50

        // Streak highlight — the hero number
        if stats.streak > 0 {
            let streakText = "🔥 连续早睡 \(stats.streak) 天"
            let streakLabel = makeLabel(text: streakText, fontSize: 24, color: .white,
                                        frame: NSRect(x: 0, y: y, width: 600, height: 36))
            streakLabel.font = NSFont.systemFont(ofSize: 24, weight: .medium)
            container.addSubview(streakLabel)
            y -= 30

            // Streak encouragement
            let encourageLabel = makeLabel(text: stats.streakMessage, fontSize: 14,
                                           color: NSColor(white: 0.5, alpha: 1.0),
                                           frame: NSRect(x: 0, y: y, width: 600, height: 22))
            container.addSubview(encourageLabel)
            y -= 16

            // Stats line: total + rate
            if stats.totalNights > 1 {
                let statsText = "累计守约 \(stats.totalCompleted) 晚 · 守约率 \(stats.rate)%"
                let statsLabel = makeLabel(text: statsText, fontSize: 13,
                                           color: NSColor(white: 0.35, alpha: 1.0),
                                           frame: NSRect(x: 0, y: y, width: 600, height: 20))
                container.addSubview(statsLabel)
                y -= 30
            } else {
                y -= 14
            }
        } else {
            // No streak — first night
            let firstLabel = makeLabel(text: "今晚是新的开始", fontSize: 18,
                                       color: NSColor(white: 0.6, alpha: 1.0),
                                       frame: NSRect(x: 0, y: y, width: 600, height: 28))
            container.addSubview(firstLabel)
            y -= 36
        }

        // Divider line (subtle)
        let divider = NSView(frame: NSRect(x: 200, y: y, width: 200, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1.0).cgColor
        container.addSubview(divider)
        y -= 24

        // Commitment message
        let messageLabel = makeLabel(text: "「\(config.message)」", fontSize: 17,
                                     color: NSColor(white: 0.55, alpha: 1.0),
                                     frame: NSRect(x: 30, y: y, width: 540, height: 44))
        messageLabel.font = NSFont.systemFont(ofSize: 17, weight: .light)
        container.addSubview(messageLabel)
        y -= 40

        // Wake time
        let wakeLabel = makeLabel(text: "起床时间 \(config.wakeupTime) · 届时自动解锁", fontSize: 13,
                                  color: NSColor(white: 0.3, alpha: 1.0),
                                  frame: NSRect(x: 0, y: y, width: 600, height: 20))
        container.addSubview(wakeLabel)
        y -= 36

        // Breathing hint
        let breatheLabel = makeLabel(text: "闭上眼睛，深呼吸，放下今天的一切", fontSize: 13,
                                     color: NSColor(white: 0.2, alpha: 1.0),
                                     frame: NSRect(x: 0, y: y, width: 600, height: 20))
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
        anim.fromValue = 0.3
        anim.toValue = 1.0
        anim.duration = 4.0
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(anim, forKey: "breathe")
    }

    func updateTime() {
        timeLabel?.stringValue = currentTimeString()
    }

    private func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateCancel
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = LockAppDelegate()
app.delegate = delegate
app.run()
