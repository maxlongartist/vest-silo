import AppKit
import SwiftUI
import WebKit

struct Snapshot: Codable {
    struct Account: Codable, Identifiable {
        let id: String
        let label: String
        let drawdown: Double?
        let limit: Double?
        let room: Double?
    }
    struct Position: Codable, Identifiable {
        let id: String
        let accountId: String
        let market: String
        let side: String
        let pnl: Double?
        var entry: Double? = nil
        var current: Double? = nil
        var fail: Double? = nil
        var failEstimated: Bool? = nil
    }
    let state: String
    let at: Double?
    let accounts: [Account]?
    let positions: [Position]?
}

func money(_ value: Double?, signed: Bool = false) -> String {
    guard let value else { return "—" }
    let sign = value < 0 ? "−" : (value > 0 && signed ? "+" : "")
    return sign + abs(value).formatted(.currency(code: "USD"))
}

enum IslandPosition: String, CaseIterable {
    case topLeft = "Top left", top = "Top", topRight = "Top right"
    case left = "Left", right = "Right"
    case bottomLeft = "Bottom left", bottom = "Bottom", bottomRight = "Bottom right"

    func origin(in bounds: CGRect, size: CGSize) -> CGPoint {
        let x: CGFloat
        switch self {
        case .topLeft, .left, .bottomLeft: x = bounds.minX
        case .topRight, .right, .bottomRight: x = bounds.maxX - size.width
        default: x = bounds.midX - size.width / 2
        }
        let y: CGFloat
        switch self {
        case .topLeft, .top, .topRight: y = bounds.maxY - size.height
        case .bottomLeft, .bottom, .bottomRight: y = bounds.minY
        default: y = bounds.midY - size.height / 2
        }
        return CGPoint(x: x, y: y)
    }
}

final class IslandModel: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var expanded = false
    @Published var position = IslandPosition(rawValue: UserDefaults.standard.string(forKey: "islandPosition") ?? "") ?? .top {
        didSet { UserDefaults.standard.set(position.rawValue, forKey: "islandPosition") }
    }
    @Published var tuckWhenCollapsed = UserDefaults.standard.bool(forKey: "tuckWhenCollapsed") {
        didSet { UserDefaults.standard.set(tuckWhenCollapsed, forKey: "tuckWhenCollapsed") }
    }
    @Published var pnlOnly = UserDefaults.standard.bool(forKey: "pnlOnly") {
        didSet { UserDefaults.standard.set(pnlOnly, forKey: "pnlOnly") }
    }
    @Published var autoHide = UserDefaults.standard.bool(forKey: "autoHide") {
        didSet { UserDefaults.standard.set(autoHide, forKey: "autoHide") }
    }
    var isPnlOnly: Bool { pnlOnly && !expanded }
    var isTucked: Bool { (tuckWhenCollapsed || pnlOnly) && !expanded }

    @Published var refreshAge: Int?
    @Published var stale = false
    let demo: Bool
    static let defaults: [String: Double] = ["width": 440, "height": 180, "opacity": 1, "fontSize": 12]
    @Published var width = IslandModel.setting("width") { didSet { UserDefaults.standard.set(width, forKey: "width") } }
    @Published var height = IslandModel.setting("height") { didSet { UserDefaults.standard.set(height, forKey: "height") } }
    @Published var opacity = IslandModel.setting("opacity") { didSet { UserDefaults.standard.set(opacity, forKey: "opacity") } }
    @Published var fontSize = IslandModel.setting("fontSize") {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }
    private static func setting(_ key: String) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? defaults[key]!
    }
    private var lastRead: Date?
    var positions: [Snapshot.Position] { snapshot?.positions ?? [] }
    var accounts: [Snapshot.Account] { snapshot?.accounts ?? [] }

    init(demo: Bool) {
        self.demo = demo
        if demo {
            snapshot = Snapshot(state: "demo", at: nil, accounts: [
                .init(id: "a", label: "#5 · 50k Eval", drawdown: 1792, limit: 3000, room: 1184),
                .init(id: "b", label: "#1 · 10k Eval", drawdown: 87.15, limit: 600, room: 370)
            ], positions: [
                .init(id: "1", accountId: "a", market: "NQ-PERP", side: "long", pnl: 184.25),
                .init(id: "2", accountId: "a", market: "BTC-PERP", side: "short", pnl: -32.16),
                .init(id: "3", accountId: "b", market: "ETH-PERP", side: "long", pnl: 21.04)
            ])
        }
    }

    func receive(_ next: Snapshot) {
        guard !demo else { return }
        if ["error", "reconnecting"].contains(next.state), snapshot?.state == "live" {
            lastRead = nil
        } else {
            snapshot = next
            lastRead = next.at.map { Date(timeIntervalSince1970: $0 / 1000) }
        }
        refresh()
    }

    func refresh() {
        guard !demo else { return }
        let age = lastRead.map { max(0, Int(Date().timeIntervalSince($0))) }
        if refreshAge != age { refreshAge = age }
        let delayed = snapshot?.state == "live" && (lastRead.map { Date().timeIntervalSince($0) > 20 } ?? true)
        if delayed != stale { stale = delayed }
    }

    var status: String {
        if demo { return "Demo" }
        if stale { return "Stale" }
        switch snapshot?.state {
        case "live": return "Connected"
        case "error": return "Read unavailable"
        case "reconnecting": return "Reconnecting…"
        default: return "Waiting for Vest"
        }
    }

    var pnl: Double? {
        guard !positions.isEmpty, positions.allSatisfy({ $0.pnl != nil }) else { return nil }
        return positions.compactMap(\.pnl).reduce(0, +)
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    let openAppearance: () -> Void
    let connectToVest: () -> Void

    var dotColor: Color {
        model.demo ? .blue : model.status == "Connected" ? .green : .orange
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    model.expanded.toggle()
                } label: {
                    HStack(spacing: 10) {
                        if model.isPnlOnly {
                            Text(money((model.demo || model.snapshot?.state == "live") && model.positions.isEmpty ? 0 : model.pnl, signed: true))
                                .monospacedDigit()
                                .foregroundStyle(model.stale ? .orange : pnlColor(model.pnl))
                                .help(model.status)
                        } else {
                            Circle().fill(dotColor).frame(width: 7, height: 7)
                            Text("Vest Silo").fontWeight(.semibold)
                            if model.demo || model.snapshot?.state == "live" {
                                Text("\(model.positions.count) open").foregroundStyle(.secondary)
                                Text(money(model.pnl, signed: true)).monospacedDigit()
                                    .foregroundStyle(pnlColor(model.pnl))
                                if model.demo || model.stale {
                                    Text(model.status).foregroundStyle(dotColor)
                                }
                            } else {
                                Text(model.status).foregroundStyle(.secondary)
                            }
                        }
                        if !model.isPnlOnly { Spacer(minLength: 0) }
                        if !model.isTucked {
                            Image(systemName: model.expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, model.isTucked ? 10 : 15)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.expanded ? "Collapse Vest Silo" : "Expand Vest Silo")
                .accessibilityValue(model.positions.isEmpty ? model.status :
                    "\(model.positions.count) open, \(money(model.pnl, signed: true))")
                if !model.isTucked {
                    Button(action: openAppearance) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Island Appearance")
                    .help("Width, height, opacity, and font size")
                }
            }

            if model.expanded {
                Divider().opacity(0.35)
                if model.accounts.isEmpty {
                    Group {
                        if model.snapshot?.state == "live" {
                            Text("No open positions or capital accounts.").foregroundStyle(.secondary)
                        } else {
                            Button("Connect to Vest to sign in", action: connectToVest)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.accounts) { account in
                                accountSection(account)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .font(.system(size: model.fontSize))
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 17).fill(Color(red: 0.055, green: 0.07, blue: 0.085)))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.14)))
    }

    func pnlColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        return value < 0 ? Color(red: 1, green: 0.48, blue: 0.49) :
            Color(red: 0.38, green: 0.85, blue: 0.69)
    }

    func price(_ value: Double?) -> String {
        value.map { "$" + $0.formatted(.number.precision(.fractionLength(2...8))) } ?? "—"
    }

    func accountSection(_ account: Snapshot.Account) -> some View {
        let positions = model.positions.filter { $0.accountId == account.id }
        let labelParts = account.label.components(separatedBy: " · ")
        let hasNumber = labelParts.first?.hasPrefix("#") == true
        let label = hasNumber && labelParts.count >= 2
            ? labelParts.prefix(2).joined(separator: " ")
            : labelParts.first ?? account.label
        let drawdown = "DD \(money(account.drawdown))/\(money(account.limit))"
        let summary = Text(label).fontWeight(.semibold)
            + Text("  \(drawdown)").foregroundColor(.secondary)
        var accountLine = summary
        if let room = account.room {
            accountLine = accountLine + Text("  Room \(money(room))")
                .foregroundColor(room <= 0 ? .red : .secondary)
        }
        if positions.isEmpty {
            accountLine = accountLine + Text("  No open positions").foregroundColor(.secondary)
        }

        let inline = positions.reduce(accountLine) { row, position in
            row + Text("  |  ") + positionLine(position)
        }
        return ViewThatFits(in: .horizontal) {
            inline.lineLimit(1).fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) {
                accountLine.fixedSize(horizontal: false, vertical: true)
                ForEach(positions) { position in
                    positionLine(position)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                }
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }

    private func positionLine(_ position: Snapshot.Position) -> Text {
        let market = position.market.replacingOccurrences(of: "-PERP", with: "")
        let side = position.side.uppercased()
        let pnl = money(position.pnl, signed: true)
        let failLabel = position.failEstimated == false ? "Fail" : "Est. fail"
        let prices = "Open \(price(position.entry))  Now \(price(position.current))  \(failLabel) \(price(position.fail))"
        return Text("\(market) \(side)").fontWeight(.medium)
            + Text("  \(pnl)").foregroundColor(pnlColor(position.pnl))
            + Text("  \(prices)").foregroundColor(.secondary)
    }

}

struct AppearanceView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 12) {
            Picker("Position", selection: $model.position) {
                ForEach(IslandPosition.allCases, id: \.self) { position in
                    Text(position.rawValue).tag(position)
                }
            }
            Toggle("Tuck away when collapsed", isOn: $model.tuckWhenCollapsed)
            Toggle("Show only total P&L when collapsed", isOn: $model.pnlOnly)
            Toggle("Auto-hide at screen edge when collapsed", isOn: $model.autoHide)
            setting("Width", value: $model.width, range: 300...900, unit: "pt")
            setting("Expanded height", value: $model.height, range: 90...780, unit: "pt")
            setting("Opacity", value: $model.opacity, range: 0.35...1, unit: "%")
            setting("Font size", value: $model.fontSize, range: 10...20, unit: "pt")
            HStack {
                Button("Reset defaults") {
                    model.width = 440
                    model.height = 180
                    model.opacity = 1
                    model.fontSize = 12
                    model.position = .top
                    model.tuckWhenCollapsed = false
                    model.pnlOnly = false
                    model.autoHide = false
                }
                Button("Quit Vest Silo") {
                    NSApp.terminate(nil)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("Donate to the dev").font(.headline)
                Text("If Vest Silo helps, tips are welcome and always optional.")
                    .foregroundStyle(.secondary)
                donation("BTC", "bc1pagpcm3j6r7cmhkeltwgkzqsrvepnfc9vt5eagclgzx6qscewqj5qdqeaxl")
                donation("EVM", "0x17e8e07a5785e1cd3b7e525da5b3003bfeca4b6f")
                donation("TRX", "TPjuRE45NaDHLNPtCThNDnzkudo5gnYq8s")
                donation("SOL", "F9qqhcqUp59GeURBB7RGbCMRU5Q77qaP3UFkq24fQQDi")
            }
        }
        .padding(20)
        .frame(width: 410)
    }

    @State private var copied: String?

    func donation(_ network: String, _ address: String) -> some View {
        HStack {
            Text(network).fontWeight(.semibold).frame(width: 34, alignment: .leading)
            Text(address).font(.system(.caption, design: .monospaced)).truncationMode(.middle).lineLimit(1)
                .textSelection(.enabled)
            Spacer()
            Button(copied == network ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                if NSPasteboard.general.setString(address, forType: .string) { copied = network }
            }
            .accessibilityLabel("Copy " + network + " address")
        }
    }

    func setting(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * (unit == "%" ? 100 : 1)).rounded())) \(unit)")
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: unit == "%" ? 0.01 : 1)
                .accessibilityLabel(title)
        }
    }
}

final class IslandPanel: NSPanel {
    var lastHover = Date.distantPast
    var targetFrame: CGRect?
    var targetOpacity: CGFloat?

    func edgeFrames(shown: CGRect, screen: CGRect, position: IslandPosition) -> (hidden: CGRect, trigger: CGRect) {
        var hidden = shown
        var trigger = shown
        switch position {
        case .left, .topLeft, .bottomLeft:
            hidden.origin.x = screen.minX - shown.width
            trigger = CGRect(x: screen.minX, y: shown.minY - 48, width: 16, height: shown.height + 96)
        case .right, .topRight, .bottomRight:
            hidden.origin.x = screen.maxX
            trigger = CGRect(x: screen.maxX - 16, y: shown.minY - 48, width: 16, height: shown.height + 96)
        case .top:
            hidden.origin.y = screen.maxY
            trigger = CGRect(x: shown.minX - 48, y: screen.maxY - 16, width: shown.width + 96, height: 16)
        case .bottom:
            hidden.origin.y = screen.minY - shown.height
            trigger = CGRect(x: shown.minX - 48, y: screen.minY, width: shown.width + 96, height: 16)
        }
        return (hidden, trigger.intersection(screen))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class IslandController: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    let model = IslandModel(demo: CommandLine.arguments.contains("--demo"))
    private var panels: [IslandPanel] = []
    private var timer: Timer?
    private var hoverTimer: Timer?
    private var state = false
    private var statusItem: NSStatusItem?
    private var settingsPanel: NSPanel?
    private var webWindow: NSWindow?
    private var syncTimer: Timer?
    private var lastRecovery: Date?
    private var recoveryAttempts = 0
    private var lastLiveUpdate: Date?
    private var syncStartedAt: Date?
    private var updateMissing: Bool {
        guard let lastUpdate = lastLiveUpdate ?? syncStartedAt else { return false }
        return Date().timeIntervalSince(lastUpdate) > 45
    }
    private var needsRecovery = false
    private var recoveryNavigation: WKNavigation?
    private var previousSize = CGSize.zero
    private var previousPosition: IslandPosition?
    private var previousTucked = false
    private var previousOpacity = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Expand / collapse", action: #selector(toggleIsland), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let connect = NSMenuItem(title: "Connect to Vest…", action: #selector(showVest), keyEquivalent: "")
        connect.target = self
        menu.addItem(connect)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit Vest Silo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "Vest Silo"
        statusItem?.menu = menu

        rebuild()
        model.refresh()
        if CommandLine.arguments.contains("--connect") {
            showVest()
        } else if UserDefaults.standard.bool(forKey: "restoresVestSession") {
            prepareVest()
        }
        let hover = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.model.autoHide, !self.model.expanded else { return }
            self.layout()
        }
        RunLoop.main.add(hover, forMode: .common)
        hoverTimer = hover
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.model.refresh()
            let size = CGSize(width: self.islandWidth, height: self.model.height)
            if self.state != self.model.expanded || self.previousSize != size || self.previousOpacity != self.model.opacity ||
                self.previousPosition != self.model.position || self.previousTucked != self.model.isTucked || self.model.autoHide || self.panels.contains(where: { $0.ignoresMouseEvents }) {
                let animate = self.previousTucked != self.model.isTucked
                self.previousTucked = self.model.isTucked
                self.previousSize = size
                self.previousPosition = self.model.position
                self.previousOpacity = self.model.opacity
                self.state = self.model.expanded
                self.layout(animate: animate)
            }
        }
    }

    @objc func showVest() {
        prepareVest()
        guard let webWindow else { return }
        if needsRecovery || updateMissing, let web = webWindow.contentView as? WKWebView {
            _ = recoverVest(web, userRequested: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        webWindow.makeKeyAndOrderFront(nil)
    }

    private func prepareVest() {
        guard !model.demo else { return }
        if webWindow == nil {
            let configuration = WKWebViewConfiguration()
            configuration.mediaTypesRequiringUserActionForPlayback = .all
            guard let id = UUID(uuidString: "BF4F6ED6-7F13-4499-A6C5-BB421C929633"),
                let url = Bundle.main.url(forResource: "session", withExtension: "js"),
                let script = try? String(contentsOf: url, encoding: .utf8) else { return }
            if #available(macOS 14.0, *) {
                configuration.websiteDataStore = .init(forIdentifier: id)
            } else {
                configuration.websiteDataStore = .nonPersistent()
            }
            configuration.userContentController.add(self, name: "islandSnapshot")
            configuration.userContentController.addUserScript(.init(source: script,
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
            let web = WKWebView(frame: .zero, configuration: configuration)
            web.navigationDelegate = self
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1100, height: 740),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Connect to Vest"
            window.isReleasedWhenClosed = false
            window.contentView = web
            window.center()
            webWindow = window
            syncStartedAt = Date()
            let timer = Timer(timeInterval: 5, repeats: true) { [weak self, weak web] _ in
                guard let self, let web else { return }
                if (self.needsRecovery || self.updateMissing), self.recoverVest(web) { return }
                web.evaluateJavaScript("window.dispatchEvent(new Event('vest-silo-refresh'))", completionHandler: nil)
            }
            RunLoop.main.add(timer, forMode: .common)
            syncTimer = timer
            if let url = URL(string: "https://next.vestmarkets.com/trade/BTC-PERP") {
                // Suspend playback before Vest can start audio in the embedded browser.
                web.setAllMediaPlaybackSuspended(true, completionHandler: { [weak web] in
                    web?.load(URLRequest(url: url))
                })
            }
        }
    }

    private func recoverVest(_ web: WKWebView, userRequested: Bool = false) -> Bool {
        let retryIntervals: [TimeInterval] = [30, 60, 120, 240, 300]
        let delay = retryIntervals[min(max(0, recoveryAttempts - 1), retryIntervals.count - 1)]
        let retryAllowed = lastRecovery.map { Date().timeIntervalSince($0) >= delay } ?? true
        guard !web.isLoading, userRequested || retryAllowed,
            web.url?.scheme == "https", web.url?.host == "next.vestmarkets.com" else { return false }
        // Let Vest restore its own login. Avoid reloading in front of someone signing in.
        guard userRequested || webWindow?.isVisible == false else { return false }
        lastRecovery = Date()
        recoveryAttempts = min(recoveryAttempts + 1, retryIntervals.count)
        recoveryNavigation = web.reload()
        return recoveryNavigation != nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        needsRecovery = true
        model.receive(Snapshot(state: "reconnecting", at: nil, accounts: nil, positions: nil))
        _ = recoverVest(webView)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.protocol == "https", origin.host == "next.vestmarkets.com",
            let text = message.body as? String, let data = text.data(using: .utf8),
            data.count < 262_144, let next = try? JSONDecoder().decode(Snapshot.self, from: data),
            ["live", "error", "disconnected", "reconnecting"].contains(next.state),
            next.state != "live" || (next.accounts != nil && next.positions != nil) else { return }
        if next.state == "live" {
            UserDefaults.standard.set(true, forKey: "restoresVestSession")
            lastLiveUpdate = Date()
            recoveryAttempts = 0
            lastRecovery = nil
            needsRecovery = false
        } else if next.state == "reconnecting" {
            needsRecovery = true
        }
        model.receive(next)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if recoveryNavigation == nil || navigation !== recoveryNavigation {
            model.receive(Snapshot(state: "disconnected", at: nil, accounts: nil, positions: nil))
        }
    }

    @objc func showSettings() {
        if settingsPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 410, height: 580),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Vest Silo Settings"
            // Keep Settings reachable even when the island fills the display.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: AppearanceView(model: model))
            panel.center()
            settingsPanel = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsPanel?.makeKeyAndOrderFront(nil)
    }

    @objc func toggleIsland() { model.expanded.toggle() }

    func applicationDidChangeScreenParameters(_ notification: Notification) { rebuild() }

    func rebuild() {
        for panel in panels { panel.orderOut(nil) }
        panels = NSScreen.screens.map { _ in
            let panel = IslandPanel(contentRect: .init(x: 0, y: 0, width: 385, height: 34),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: IslandView(
                model: model,
                openAppearance: { [weak self] in self?.showSettings() },
                connectToVest: { [weak self] in self?.showVest() }
            ))
            return panel
        }
        layout()
        for panel in panels { panel.orderFrontRegardless() }
    }

    private var islandWidth: CGFloat {
        if model.isPnlOnly {
            let text = money((model.demo || model.snapshot?.state == "live") && model.positions.isEmpty ? 0 : model.pnl, signed: true)
            return min(model.width, max(70, (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: model.fontSize)]).width + 24))
        }
        return model.isTucked ? min(model.width, max(208, 18 * model.fontSize)) : model.width
    }

    func layout(animate: Bool = false, mouseLocation: CGPoint = NSEvent.mouseLocation) {
        for (panel, screen) in zip(panels, NSScreen.screens) {
            let visible = screen.visibleFrame
            let safeTop = screen.frame.maxY - max(screen.safeAreaInsets.top, 24)
            let bounds = CGRect(x: visible.minX + 8, y: visible.minY + 8,
                width: max(1, visible.width - 16),
                height: max(1, min(visible.maxY, safeTop) - visible.minY - 12))
            let size = CGSize(width: min(islandWidth, bounds.width),
                height: min(model.expanded ? CGFloat(model.height) : 34, bounds.height))
            let origin = model.position.origin(in: bounds, size: size)
            let shown = CGRect(origin: origin, size: size)
            let edges = panel.edgeFrames(shown: shown, screen: screen.frame, position: model.position)
            let mouse = mouseLocation
            let autoHide = model.autoHide && !model.expanded
            if edges.trigger.contains(mouse) || (!panel.ignoresMouseEvents && edges.trigger.union(shown).insetBy(dx: -8, dy: -8).contains(mouse)) {
                panel.lastHover = Date()
            }
            let hidden = autoHide && Date().timeIntervalSince(panel.lastHover) > 1.2
            let frame = hidden ? edges.hidden : shown
            let changed = panel.ignoresMouseEvents != hidden
            panel.ignoresMouseEvents = hidden
            let opacity = hidden ? 0 : CGFloat(model.opacity)
            guard panel.targetFrame != frame || panel.targetOpacity != opacity else { continue }
            panel.targetFrame = frame
            panel.targetOpacity = opacity
            if (animate || changed), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    panel.animator().alphaValue = opacity
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.alphaValue = opacity
                panel.setFrame(frame, display: true)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = IslandController()
app.delegate = controller
app.run()
