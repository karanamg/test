import Foundation
import Network
import Observation
import UIKit
import UserNotifications

struct PingPoint: Identifiable {
    let id = UUID()
    let date: Date
    let ms: Double?
}

@MainActor
@Observable
final class MeetMonitor {
    enum Link: String {
        case wifi = "Wi-Fi", cellular = "Cellular", wired = "Ethernet", other = "Other", none = "Not connected"
    }

    // Connection
    private(set) var link: Link = .none
    private(set) var isLowDataMode = false

    // Measurements
    private(set) var pings: [PingPoint] = []
    private(set) var downloadMbps: Double?
    private(set) var uploadMbps: Double?
    private(set) var lastSpeedTest: Date?
    private(set) var isSpeedTesting = false

    // State
    private(set) var isRunning = false
    private(set) var level: Level = .excellent
    private(set) var reasons: [String] = []

    // Settings
    var alertsEnabled = true
    var speedTestEvery: TimeInterval = 120

    private let window = 30          // pings used for stats (~30 s)
    private let historyLimit = 120   // pings kept for the chart (~2 min)

    private let pathMonitor = NWPathMonitor()
    private var pingTask: Task<Void, Never>?
    private var speedTask: Task<Void, Never>?
    private var badStreak = 0
    private var alertedLevel: Level?
    private var lastAlert = Date.distantPast

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.pathChanged(path) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "MeetReady.path"))
    }

    var stats: LinkStats { LinkStats(samples: pings.suffix(window).map(\.ms)) }
    var isMeasuring: Bool { isRunning && pings.count < 5 }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        isRunning = true
        pings.removeAll()
        badStreak = 0
        alertedLevel = nil
        UIApplication.shared.isIdleTimerDisabled = true
        requestNotificationPermission()

        pingTask = Task { [weak self] in
            // First request opens the connection; don't count the handshake.
            _ = await Probe.ping()
            while !Task.isCancelled {
                let started = Date()
                let ms = await Probe.ping()
                guard let self, !Task.isCancelled else { return }
                self.record(ms)
                let wait = max(0.2, 1 - Date().timeIntervalSince(started))
                try? await Task.sleep(for: .seconds(wait))
            }
        }

        speedTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runSpeedTest()
                try? await Task.sleep(for: .seconds(self.speedTestEvery))
            }
        }
    }

    func stop() {
        isRunning = false
        pingTask?.cancel()
        speedTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func runSpeedTest() async {
        guard !isSpeedTesting, link != .none else { return }
        isSpeedTesting = true
        defer { isSpeedTesting = false }
        downloadMbps = await Probe.downloadMbps() ?? 0
        uploadMbps = await Probe.uploadMbps() ?? 0
        lastSpeedTest = Date()
        evaluate()
    }

    // MARK: - Internals

    private func pathChanged(_ path: NWPath) {
        let old = link
        if path.status != .satisfied {
            link = .none
        } else if path.usesInterfaceType(.wifi) {
            link = .wifi
        } else if path.usesInterfaceType(.cellular) {
            link = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            link = .wired
        } else {
            link = .other
        }
        isLowDataMode = path.isConstrained

        guard isRunning, old != link else { return }
        if old == .wifi {
            notify(title: "Wi-Fi lost",
                   body: link == .none ? "You are offline." : "Switched to \(link.rawValue). Your call may use mobile data.")
        } else if link == .wifi {
            notify(title: "Wi-Fi connected", body: "Re-checking call quality…")
            downloadMbps = nil
            uploadMbps = nil
            Task { await runSpeedTest() }
        }
        evaluate()
    }

    private func record(_ ms: Double?) {
        pings.append(PingPoint(date: Date(), ms: ms))
        if pings.count > historyLimit { pings.removeFirst(pings.count - historyLimit) }
        evaluate()
    }

    private func evaluate() {
        guard pings.count >= 5 || link == .none else { return }
        let result = Grader.assess(online: link != .none, stats: stats,
                                   download: downloadMbps, upload: uploadMbps)
        level = result.level
        reasons = result.reasons
        if link == .cellular { reasons.insert("You're not on Wi-Fi – the call will use mobile data.", at: 0) }
        if isLowDataMode { reasons.append("Low Data Mode is on – Meet may limit video quality.") }
        checkAlerts()
    }

    /// Alert only when quality stays bad for a few seconds, to avoid noise
    /// from a single slow ping.
    private func checkAlerts() {
        guard isRunning else { return }
        if level <= .fair {
            badStreak += 1
            let worseThanLastAlert = alertedLevel.map { level < $0 } ?? true
            if badStreak >= 5 && worseThanLastAlert && Date().timeIntervalSince(lastAlert) > 30 {
                alertedLevel = level
                notify(title: "Connection \(level.title.lowercased())", body: reasons.first ?? level.callAdvice)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        } else {
            badStreak = 0
            if alertedLevel != nil {
                alertedLevel = nil
                notify(title: "Connection is good again", body: level.callAdvice)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard alertsEnabled else { return }
        lastAlert = Date()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
