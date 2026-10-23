import AppKit

struct Window: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Int { Int(max(0, min(100, 100 - usedPercent)).rounded()) }
    var label: String {
        guard let minutes = windowDurationMins else { return "用量窗口" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }
}
struct Bucket: Decodable {
    let limitName: String?
    let primary: Window?
    let secondary: Window?
}
struct Limits: Decodable {
    let rateLimits: Bucket?
    let rateLimitsByLimitId: [String: Bucket]?
    var buckets: [(String, Bucket)] {
        if let all = rateLimitsByLimitId, !all.isEmpty {
            return all.sorted { a, b in
                if a.key == "codex" { return b.key != "codex" }
                if b.key == "codex" { return false }
                return a.key < b.key
            }.map { ($0.key, $0.value) }
        }
        return rateLimits.map { [("Codex", $0)] } ?? []
    }
}
struct UsageError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Only initializes the protocol and reads limits. No conversations or model turns.
func fetchLimits(executable: String) throws -> Limits {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["app-server"]
    let input = Pipe(), output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: timeout)
    defer {
        timeout.cancel()
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }
    func send(_ value: [String: Any]) throws {
        var bytes = try JSONSerialization.data(withJSONObject: value)
        bytes.append(10)
        try input.fileHandleForWriting.write(contentsOf: bytes)
    }
    try send(["id": 0, "method": "initialize", "params": ["clientInfo": ["name": "codex_usage_menu", "version": "0.1.0"]]])
    var buffer = Data()
    while true {
        let chunk = output.fileHandleForReading.availableData
        if chunk.isEmpty { throw UsageError(message: "无法读取用量：连接退出或超时。请检查 Codex 登录和网络。") }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = message["id"] as? Int else { continue }
            if message["error"] != nil { throw UsageError(message: "Codex 未返回用量，请确认已使用 ChatGPT 账号登录。") }
            if id == 0 {
                try send(["method": "initialized", "params": [:]])
                try send(["id": 1, "method": "account/rateLimits/read"])
            } else if id == 1, let result = message["result"] {
                return try JSONDecoder().decode(Limits.self, from: JSONSerialization.data(withJSONObject: result))
            }
        }
    }
}

// A compact vector companion head, drawn at native menu-bar size.
func companionIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
        let outline = NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.43, alpha: 1)
        let shell = NSBezierPath()
        shell.move(to: NSPoint(x: 1, y: 5))
        for (x, y) in [(1,12),(3,12),(3,15),(6,15),(6,17),(12,17),(12,16),(15,16),(15,14),(17,14),(17,12),(19,12),(19,5),(17,5),(17,2),(14,2),(14,1),(5,1),(5,2),(3,2),(3,5)] {
            shell.line(to: NSPoint(x: x, y: y))
        }
        shell.close()
        NSColor(calibratedRed: 0.35, green: 0.50, blue: 0.98, alpha: 1).setFill()
        shell.fill()
        outline.setStroke()
        shell.lineWidth = 1
        shell.stroke()
        let screen = NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 12, height: 9), xRadius: 2, yRadius: 2)
        outline.setFill()
        screen.fill()
        let face = NSBezierPath()
        face.move(to: NSPoint(x: 6.5, y: 10.5))
        face.line(to: NSPoint(x: 9, y: 8.5))
        face.line(to: NSPoint(x: 6.5, y: 6.5))
        face.move(to: NSPoint(x: 11, y: 6.5))
        face.line(to: NSPoint(x: 14, y: 6.5))
        face.lineWidth = 1.5
        face.lineCapStyle = .round
        face.lineJoinStyle = .round
        NSColor(calibratedRed: 0.51, green: 0.96, blue: 1, alpha: 1).setStroke()
        face.stroke()
        return true
    }
    image.isTemplate = false
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var limits: Limits?
    var lastUpdate: Date?
    var failure: String?
    var loading = false
    var timer: Timer?
    var executable: String? {
        let custom = UserDefaults.standard.string(forKey: "codexExecutable")
        let candidates = [custom,
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/bin/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        status.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        status.button?.image = companionIcon()
        status.button?.imagePosition = .imageLeading
        status.button?.imageHugsTitle = false
        status.menu = menu
        menu.delegate = self
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }
    func menuWillOpen(_ menu: NSMenu) { render() }
    func row(_ title: String) { menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
    func action(_ title: String, _ selector: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
    func render() {
        let prefix = failure == nil ? "" : "⚠︎ "
        if let first = limits?.buckets.first?.1 {
            let windows = [first.primary, first.secondary].compactMap { $0 }
            status.button?.title = prefix + " " + (windows.isEmpty ? "—" : windows.map { "\($0.remaining)%" }.joined(separator: " / "))
        } else { status.button?.title = loading ? " …" : " —" }
        status.button?.toolTip = "Codex 剩余用量 · 每 60 秒刷新" + (failure == nil ? "" : " · 数据可能已过期")
        menu.removeAllItems()
        row("Codex 剩余用量")
        menu.addItem(.separator())
        if let limits {
            for (key, bucket) in limits.buckets {
                row(bucket.limitName ?? key)
                for window in [bucket.primary, bucket.secondary].compactMap({ $0 }) {
                    row("\(window.label) · 剩余 \(window.remaining)%")
                    if let reset = window.resetsAt {
                        row("重置：" + Date(timeIntervalSince1970: reset).formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if bucket.primary == nil && bucket.secondary == nil { row("暂无窗口数据") }
                menu.addItem(.separator())
            }
            if limits.buckets.isEmpty { row("账号未返回用量窗口") }
        }
        if let failure { row(failure); row("已有数值为上次成功读取，可能已过期") }
        if let lastUpdate { row("更新于 " + lastUpdate.formatted(date: .omitted, time: .standard)) }
        row("每 60 秒刷新")
        action(loading ? "正在刷新…" : "立即刷新", #selector(refresh), key: "r")
        menu.items.last?.isEnabled = !loading
        menu.addItem(.separator())
        action("选择 Codex 可执行文件…", #selector(selectExecutable))
        action("打开 Codex", #selector(openCodex))
        action("退出", #selector(quit), key: "q")
    }
    @objc func refresh() {
        guard !loading else { return }
        guard let path = executable else {
            failure = "未找到 Codex，请选择可执行文件。"
            render()
            return
        }
        loading = true
        render()
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try fetchLimits(executable: path) }
            DispatchQueue.main.async {
                self.loading = false
                switch result {
                case .success(let limits): self.limits = limits; self.lastUpdate = Date(); self.failure = nil
                case .failure(let error): self.failure = error.localizedDescription
                }
                self.render()
            }
        }
    }
    @objc func selectExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.message = "选择 Codex CLI 可执行文件（codex）"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "codexExecutable")
            refresh()
        }
    }
    @objc func openCodex() {
        let path = FileManager.default.fileExists(atPath: "/Applications/Codex.app") ? "/Applications/Codex.app" : "/Applications/ChatGPT.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
    @objc func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--probe") {
    let path = CommandLine.arguments.last!
    do {
        let limits = try fetchLimits(executable: path)
        for (name, bucket) in limits.buckets {
            print(name + ": " + [bucket.primary, bucket.secondary].compactMap { $0 }.map { "\($0.label) 剩余 \($0.remaining)%" }.joined(separator: ", "))
        }
        exit(0)
    } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
