import SwiftUI

enum Level: Int, Comparable, CaseIterable {
    case offline, poor, fair, good, excellent

    static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .offline: "No connection"
        case .poor: "Poor"
        case .fair: "Fair"
        case .good: "Good"
        case .excellent: "Excellent"
        }
    }

    var callAdvice: String {
        switch self {
        case .offline: "You can't join a call right now."
        case .poor: "Expect frozen video. Use audio only."
        case .fair: "Audio is fine. Video may drop to low quality."
        case .good: "Video calls should work well."
        case .excellent: "Ready for HD video calls."
        }
    }

    var color: Color {
        switch self {
        case .offline: .gray
        case .poor: .red
        case .fair: .orange
        case .good: .green
        case .excellent: .mint
        }
    }

    var symbol: String {
        switch self {
        case .offline: "wifi.slash"
        case .poor: "wifi.exclamationmark"
        case .fair, .good, .excellent: "wifi"
        }
    }
}

/// Summary of the recent ping window.
struct LinkStats {
    var latencyMs: Double?   // median round trip
    var jitterMs: Double?    // mean change between consecutive pings
    var lossPercent: Double  // share of pings that got no answer
    var sampleCount: Int

    init(samples: [Double?]) {
        sampleCount = samples.count
        let ok = samples.compactMap { $0 }
        lossPercent = samples.isEmpty ? 0 : Double(samples.count - ok.count) / Double(samples.count) * 100
        if ok.isEmpty {
            latencyMs = nil
        } else {
            let sorted = ok.sorted()
            latencyMs = sorted[sorted.count / 2]
        }
        if ok.count >= 2 {
            let diffs = zip(ok.dropFirst(), ok).map { abs($0 - $1) }
            jitterMs = diffs.reduce(0, +) / Double(diffs.count)
        } else {
            jitterMs = nil
        }
    }
}

/// Grades each metric against Google Meet's published bandwidth needs
/// (about 2.6–3.2 Mbps each way for HD video, ~1 Mbps for basic video)
/// and common real-time thresholds for latency, jitter and loss.
/// The overall level is the worst of the individual grades.
enum Grader {
    static func latency(_ ms: Double) -> Level {
        switch ms {
        case ..<80: .excellent
        case ..<150: .good
        case ..<300: .fair
        default: .poor
        }
    }

    static func jitter(_ ms: Double) -> Level {
        switch ms {
        case ..<15: .excellent
        case ..<30: .good
        case ..<60: .fair
        default: .poor
        }
    }

    static func loss(_ pct: Double) -> Level {
        switch pct {
        case ..<0.5: .excellent
        case ..<2: .good
        case ..<5: .fair
        default: .poor
        }
    }

    static func download(_ mbps: Double) -> Level {
        switch mbps {
        case 5...: .excellent
        case 3.2...: .good
        case 1...: .fair
        default: .poor
        }
    }

    static func upload(_ mbps: Double) -> Level {
        switch mbps {
        case 4...: .excellent
        case 2.6...: .good
        case 1...: .fair
        default: .poor
        }
    }

    struct Result {
        var level: Level
        var reasons: [String]
    }

    static func assess(online: Bool, stats: LinkStats, download: Double?, upload: Double?) -> Result {
        guard online else { return Result(level: .offline, reasons: ["Your phone has no network connection."]) }
        if stats.sampleCount >= 5 && stats.lossPercent >= 99 {
            return Result(level: .offline, reasons: ["Connected, but nothing is reaching the internet."])
        }

        var level = Level.excellent
        var reasons: [String] = []
        func apply(_ l: Level, _ why: String) {
            level = min(level, l)
            if l <= .fair { reasons.append(why) }
        }

        if let ms = stats.latencyMs { apply(latency(ms), "High delay (\(Int(ms)) ms) – people will talk over each other.") }
        if let ms = stats.jitterMs { apply(jitter(ms), "Unstable timing (jitter \(Int(ms)) ms) – choppy audio likely.") }
        apply(loss(stats.lossPercent), String(format: "Losing %.0f%% of packets – video will freeze.", stats.lossPercent))
        if let d = download { apply(Grader.download(d), String(format: "Download only %.1f Mbps – others' video will blur.", d)) }
        if let u = upload { apply(Grader.upload(u), String(format: "Upload only %.1f Mbps – your video will look blurry to others.", u)) }

        return Result(level: level, reasons: reasons)
    }
}
