import AppKit
import Carbon.HIToolbox

struct Win: Codable { let label: String; let percentUsed: Double; let resetsAt: String }
struct Snap: Codable { let updated: String?; let windows: [Win] }
struct Rec: Codable { let ts: String; let session: String?; let project: String?; let five: Double?; let seven: Double?; let cost: Double? }

let home = NSString(string: "~/.claude-usage-widget/").expandingTildeInPath + "/"
let isFR = Locale.preferredLanguages.first?.hasPrefix("fr") ?? false
func T(_ f: String, _ e: String) -> String { isFR ? f : e }
func dispName(_ l: String) -> String { l.hasPrefix("Session") ? T("Session de 5 h", "5-hour session") : l.contains("tous") ? T("Semaine · tous modèles", "Week · all models") : l }
let isoF: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
let isoP = ISO8601DateFormatter()
func parse(_ s: String) -> Date? { isoF.date(from: s) ?? isoP.date(from: s) }
func fmt(_ p: String) -> DateFormatter { let f = DateFormatter(); f.locale = Locale(identifier: isFR ? "fr_FR" : "en_US"); f.dateFormat = p; return f }
let dfFull = fmt("EEE d MMM HH:mm"), dfHour = fmt("HH:mm"), dfDay = fmt("EEE d MMM")
let ud = UserDefaults.standard

var compact = false, historyMode = false
var scale: CGFloat { CGFloat(ud.object(forKey: "scale") as? Double ?? 1.0) }
func dur(_ m: Int) -> String { m >= 60 ? "\(m/60) h \(m%60) min" : "\(m) min" }

func loadSnap() -> Snap? { FileManager.default.contents(atPath: home + "usage-widget.json").flatMap { try? JSONDecoder().decode(Snap.self, from: $0) } }
func loadHistory() -> [Rec] {
    guard let s = try? String(contentsOfFile: home + "usage-history.jsonl", encoding: .utf8) else { return [] }
    return s.split(separator: "\n").compactMap { try? JSONDecoder().decode(Rec.self, from: Data($0.utf8)) }
}

func windowLength(_ label: String) -> TimeInterval { label.hasPrefix("Session") ? 5*3600 : 7*86400 }
func value(_ r: Rec, _ label: String) -> Double? { label.hasPrefix("Session") ? r.five : label.contains("tous") ? r.seven : nil }

// Prévision : pente sur les relevés de la fenêtre en cours
func forecast(_ w: Win, _ hist: [Rec]) -> (text: String, danger: Bool)? {
    guard let reset = parse(w.resetsAt), w.percentUsed < 100 else { return nil }
    let start = reset.addingTimeInterval(-windowLength(w.label))
    let pts = hist.compactMap { r -> (Date, Double)? in
        guard let d = parse(r.ts), d >= start, d <= reset, let v = value(r, w.label) else { return nil }; return (d, v) }
    guard let first = pts.first, let last = pts.last, last.0.timeIntervalSince(first.0) > 600, last.1 > first.1 else {
        return (T("Prévision : données insuffisantes", "Forecast: not enough data yet"), false) }
    let rate = (last.1 - first.1) / last.0.timeIntervalSince(first.0)
    let eta = last.0.addingTimeInterval((100 - last.1) / rate)
    if eta < reset { return (T("⚠︎ Limite atteinte vers \(dfHour.string(from: eta)), avant la remise à zéro", "⚠︎ Limit reached around \(dfHour.string(from: eta)), before the reset"), true) }
    return (T("Rythme OK jusqu'à la remise à zéro", "Pace OK until the reset"), false)
}

func label(_ t: String, _ size: CGFloat, _ weight: NSFont.Weight, secondary: Bool = false, color: NSColor? = nil) -> NSTextField {
    let l = NSTextField(labelWithString: t)
    l.font = .systemFont(ofSize: size * scale, weight: weight)
    l.textColor = color ?? (secondary ? .secondaryLabelColor : .labelColor)
    l.lineBreakMode = .byWordWrapping; l.maximumNumberOfLines = 0
    l.preferredMaxLayoutWidth = 268 * scale
    return l
}

func menuText() -> String {
    guard let s = loadSnap(), !s.windows.isEmpty else { return "Claude" }
    return s.windows.prefix(2).map { "\(Int($0.percentUsed))%" }.joined(separator: " · ")
}

func buildHistory() -> [NSView] {
    let hist = loadHistory()
    let cal = Calendar.current
    var perSession: [String: (day: Date, project: String, cost: Double)] = [:]
    for r in hist {
        guard let d = parse(r.ts), let c = r.cost, let id = r.session, !id.isEmpty else { continue }
        let key = id
        if (perSession[key]?.cost ?? -1) < c { perSession[key] = (cal.startOfDay(for: d), r.project ?? "?", c) }
    }
    guard !perSession.isEmpty else { return [label(T("Pas encore d'historique : il se remplit pendant vos sessions Claude Code.", "No history yet: it fills up during your Claude Code sessions."), 11, .regular, secondary: true)] }
    var views: [NSView] = [label(T("Historique · coût estimé par jour", "History · estimated cost per day"), 12, .semibold)]
    let days = Dictionary(grouping: perSession.values, by: { $0.day }).sorted { $0.key > $1.key }.prefix(7)
    for (day, items) in days {
        let total = items.reduce(0) { $0 + $1.cost }
        var byProj: [String: Double] = [:]; items.forEach { byProj[$0.project, default: 0] += $0.cost }
        let top = byProj.sorted { $0.value > $1.value }.prefix(2).map { "\($0.key) \(String(format: "%.2f", $0.value)) $" }.joined(separator: ", ")
        views.append(label("\(dfDay.string(from: day)) · \(String(format: "%.2f", total)) $", 11.5, .medium))
        views.append(label(top, 10.5, .regular, secondary: true))
    }
    return views
}

func build() -> NSView {
    let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8 * scale
    stack.edgeInsets = NSEdgeInsets(top: 16 * scale, left: 16 * scale, bottom: 16 * scale, right: 16 * scale)
    let width = 268 * scale
    func add(_ v: NSView) { stack.addArrangedSubview(v); v.widthAnchor.constraint(equalToConstant: width).isActive = true }
    if historyMode { buildHistory().forEach(add); return stack }
    guard let s = loadSnap(), !s.windows.isEmpty else {
        add(label(T("Aucune donnée : ouvrez une session Claude Code.", "No data yet: open a Claude Code session."), 11, .regular, secondary: true)); return stack }
    let hist = loadHistory()
    for w in (compact ? Array(s.windows.prefix(1)) : s.windows) {
        let head = NSStackView(); head.orientation = .horizontal; head.distribution = .fill
        head.addArrangedSubview(label(dispName(w.label), 12, .semibold)); head.addArrangedSubview(NSView())
        head.addArrangedSubview(label(T("\(Int(w.percentUsed)) % · reste \(100 - Int(w.percentUsed)) %", "\(Int(w.percentUsed)) % used · \(100 - Int(w.percentUsed)) % left"), 11, .regular, secondary: true))
        let bar = NSProgressIndicator(); bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 100; bar.doubleValue = w.percentUsed
        bar.controlSize = .small
        var sub = "↺ ?"
        if let d = parse(w.resetsAt) {
            let m = max(0, Int(d.timeIntervalSinceNow / 60))
            sub = T("↺ \(dfFull.string(from: d)) · dans \(dur(m))", "↺ \(dfFull.string(from: d)) · in \(dur(m))")
        }
        add(head); add(bar); add(label(sub, 10.5, .regular, secondary: true))
        if !compact, let f = forecast(w, hist) {
            add(label(f.text, 10.5, f.danger ? .semibold : .regular, secondary: !f.danger, color: f.danger ? .systemRed : nil))
        }
    }
    return stack
}

func notify(_ title: String, _ body: String) {
    let esc = { (s: String) in s.replacingOccurrences(of: "\"", with: "'") }
    let p = Process(); p.launchPath = "/usr/bin/osascript"
    p.arguments = ["-e", "display notification \"\(esc(body))\" with title \"\(esc(title))\" sound name \"Glass\""]
    try? p.run()
}

func checkAlerts() {
    guard let s = loadSnap() else { return }
    for w in s.windows {
        for t in [70.0, 90.0, 100.0] where w.percentUsed >= t {
            let key = "n|\(w.label)|\(w.resetsAt)|\(Int(t))"
            if !ud.bool(forKey: key) {
                ud.set(true, forKey: key)
                notify(dispName(w.label), t >= 100 ? T("Limite atteinte (100 %).", "Limit reached (100%).") : T("\(Int(t)) % de la limite utilisés.", "\(Int(t))% of your limit used."))
            }
        }
        if w.percentUsed >= 100, let r = parse(w.resetsAt), r < Date() {
            let key = "free|\(w.label)|\(w.resetsAt)"
            if !ud.bool(forKey: key) { ud.set(true, forKey: key); notify(dispName(w.label), T("La limite est libérée : vous pouvez reprendre.", "Your limit has reset: you can resume.")) }
        }
    }
    // une limite pleine dont la fenêtre est passée sans relevé : prévenir quand même
    for k in ud.dictionaryRepresentation().keys where k.hasPrefix("n|") && k.hasSuffix("|100") {
        let parts = k.split(separator: "|").map(String.init)
        if parts.count == 4, let r = parse(parts[2]), r < Date() {
            let key = "free|\(parts[1])|\(parts[2])"
            if !ud.bool(forKey: key) { ud.set(true, forKey: key); notify(dispName(parts[1]), T("La limite est libérée : vous pouvez reprendre.", "Your limit has reset: you can resume.")) }
        }
    }
}

class Dragger: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func rightMouseDown(with e: NSEvent) { NSMenu.popUpContextMenu((NSApp.delegate as! AppDelegate).makeMenu(), with: e, for: self) }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var sigSrc: DispatchSourceSignal?; var win: NSWindow!; let fx = Dragger(); var status: NSStatusItem!
    func applicationDidFinishLaunching(_ n: Notification) {
        fx.material = .hudWindow; fx.blendingMode = .behindWindow; fx.state = .active
        fx.wantsLayer = true; fx.layer?.cornerRadius = 24; fx.layer?.masksToBounds = true
        win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.hasShadow = true
        win.level = .floating; win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.contentView = fx
        win.alphaValue = CGFloat(ud.object(forKey: "alpha") as? Double ?? 1.0)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()
        if !win.setFrameUsingName("UsageWidget") { win.center() }
        win.setFrameAutosaveName("UsageWidget")
        win.makeKeyAndOrderFront(nil)
        registerHotkey()
        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { self.refresh() }; src.resume(); sigSrc = src
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in checkAlerts(); self.status.button?.title = menuText() }
    }
    func makeMenu() -> NSMenu {
        let m = NSMenu()
        func item(_ t: String, _ a: Selector, _ tag: Int = 0, on: Bool = false) {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: ""); i.target = self; i.tag = tag; i.state = on ? .on : .off; m.addItem(i) }
        item(T("Rafraîchir", "Refresh"), #selector(doRefresh))
        item(historyMode ? T("Retour à la consommation", "Back to usage") : T("Historique", "History"), #selector(toggleHistory))
        item(compact ? T("Agrandir", "Expand") : T("Réduire", "Compact"), #selector(toggleCompact))
        m.addItem(.separator())
        let tr = NSMenuItem(title: T("Transparence", "Transparency"), action: nil, keyEquivalent: ""); let ts = NSMenu()
        for p in [100, 85, 70, 50] { let i = NSMenuItem(title: "\(p) %", action: #selector(setAlpha(_:)), keyEquivalent: ""); i.target = self; i.tag = p
            i.state = Int((win.alphaValue * 100).rounded()) == p ? .on : .off; ts.addItem(i) }
        tr.submenu = ts; m.addItem(tr)
        let sz = NSMenuItem(title: T("Taille", "Size"), action: nil, keyEquivalent: ""); let ss = NSMenu()
        for (n, v) in [(T("Petit", "Small"), 85), (T("Normal", "Normal"), 100), (T("Grand", "Large"), 120)] { let i = NSMenuItem(title: n, action: #selector(setScale(_:)), keyEquivalent: ""); i.target = self; i.tag = v
            i.state = Int((scale * 100).rounded()) == v ? .on : .off; ss.addItem(i) }
        sz.submenu = ss; m.addItem(sz)
        m.addItem(.separator())
        item(win.isVisible ? T("Masquer le widget", "Hide widget") : T("Afficher le widget", "Show widget"), #selector(toggleShow))
        item(T("Quitter", "Quit"), #selector(quitApp))
        return m
    }
    @objc func doRefresh() { refresh() }
    @objc func toggleCompact() { compact.toggle(); historyMode = false; refresh() }
    @objc func toggleHistory() { historyMode.toggle(); refresh() }
    @objc func setAlpha(_ s: NSMenuItem) { ud.set(Double(s.tag) / 100, forKey: "alpha"); win.alphaValue = CGFloat(s.tag) / 100 }
    @objc func setScale(_ s: NSMenuItem) { ud.set(Double(s.tag) / 100, forKey: "scale"); refresh() }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func toggleShow() { if win.isVisible { win.orderOut(nil) } else { refresh(); win.makeKeyAndOrderFront(nil) } }
    func registerHotkey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { (NSApp.delegate as! AppDelegate).toggleShow() }; return noErr }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_U), UInt32(cmdKey | optionKey | controlKey), EventHotKeyID(signature: OSType(0x43555731), id: 1), GetApplicationEventTarget(), 0, &ref)
    }
    func refresh() {
        fx.subviews.forEach { $0.removeFromSuperview() }
        let v = build(); v.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(v)
        NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: fx.leadingAnchor), v.topAnchor.constraint(equalTo: fx.topAnchor)])
        let size = v.fittingSize
        var f = win.frame; f.origin.y += f.height - size.height; f.size = size
        win.setFrame(f, display: true)
        status.button?.title = menuText(); status.menu = makeMenu()
        checkAlerts()
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let del = AppDelegate(); app.delegate = del
app.run()
