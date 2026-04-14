import Cocoa

// MARK: - Config

struct SleepConfig {
    let message: String
    let wakeupTime: String  // "HH:MM"
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

// MARK: - Lock Window

class LockWindowController {
    let config: SleepConfig
    var windows: [NSWindow] = []
    var clockTimer: Timer?

    init(config: SleepConfig) {
        self.config = config
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
        let contentView = LockScreenView(frame: localFrame, config: config)
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
    private var timeLabel: NSTextField!
    private var messageLabel: NSTextField!
    private var subtitleLabel: NSTextField!

    init(frame: NSRect, config: SleepConfig) {
        self.config = config
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let container = NSView(frame: NSRect(
            x: bounds.midX - 300,
            y: bounds.midY - 150,
            width: 600,
            height: 300
        ))
        container.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        addSubview(container)

        // Moon icon
        let moonLabel = makeLabel(
            text: "🌙",
            fontSize: 48,
            color: .white,
            frame: NSRect(x: 0, y: 220, width: 600, height: 60)
        )
        container.addSubview(moonLabel)

        // Time
        timeLabel = makeLabel(
            text: currentTimeString(),
            fontSize: 72,
            color: .white,
            frame: NSRect(x: 0, y: 130, width: 600, height: 90)
        )
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 72, weight: .ultraLight)
        container.addSubview(timeLabel)

        // Commitment message
        messageLabel = makeLabel(
            text: config.message,
            fontSize: 20,
            color: NSColor(white: 0.7, alpha: 1.0),
            frame: NSRect(x: 20, y: 70, width: 560, height: 50)
        )
        container.addSubview(messageLabel)

        // Subtitle
        subtitleLabel = makeLabel(
            text: "起床时间 \(config.wakeupTime) · 届时自动解锁",
            fontSize: 14,
            color: NSColor(white: 0.4, alpha: 1.0),
            frame: NSRect(x: 0, y: 20, width: 600, height: 30)
        )
        container.addSubview(subtitleLabel)

        // Bottom breathing hint
        let breatheLabel = makeLabel(
            text: "闭上眼睛，深呼吸，放下今天的一切",
            fontSize: 13,
            color: NSColor(white: 0.25, alpha: 1.0),
            frame: NSRect(x: 0, y: -40, width: 600, height: 25)
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
        controller = LockWindowController(config: config)
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
