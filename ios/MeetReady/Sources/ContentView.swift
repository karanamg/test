import Charts
import SwiftUI

struct ContentView: View {
    @State private var monitor = MeetMonitor()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    StatusHeader(monitor: monitor)
                    ConnectionRow(monitor: monitor)
                    MetricsGrid(monitor: monitor)
                    if monitor.isRunning && !monitor.pings.isEmpty {
                        LatencyChart(pings: monitor.pings)
                    }
                    if monitor.isRunning && !monitor.isMeasuring && !monitor.reasons.isEmpty {
                        ReasonsCard(reasons: monitor.reasons)
                    }
                    Controls(monitor: monitor)
                    SettingsCard(monitor: monitor)
                    Text("Keep MeetReady open before and between calls. iOS pauses apps in the background, so it can't keep testing while Meet is on screen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("MeetReady")
        }
        .onAppear { monitor.start() }
    }
}

// MARK: - Header

private struct StatusHeader: View {
    let monitor: MeetMonitor

    var body: some View {
        let level = monitor.level
        let idle = !monitor.isRunning
        let measuring = monitor.isMeasuring && monitor.link != .none
        let color: Color = idle || measuring ? .secondary : level.color

        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 160, height: 160)
                Circle()
                    .stroke(color, lineWidth: 8)
                    .frame(width: 160, height: 160)
                if measuring {
                    ProgressView().controlSize(.large)
                } else {
                    Image(systemName: idle ? "pause.fill" : level.symbol)
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(color)
                        .symbolEffect(.pulse, isActive: !idle && level <= .fair)
                }
            }
            Text(idle ? "Paused" : measuring ? "Checking…" : level.title)
                .font(.largeTitle.bold())
            Text(idle ? "Tap Start to monitor your connection." :
                 measuring ? "Measuring your connection to Google." : level.callAdvice)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .animation(.easeInOut, value: level)
    }
}

private struct ConnectionRow: View {
    let monitor: MeetMonitor

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(monitor.link == .wifi ? .blue : .orange)
            Text(monitor.link.rawValue).bold()
            Spacer()
            if monitor.isLowDataMode {
                Label("Low Data Mode", systemImage: "tortoise.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private var icon: String {
        switch monitor.link {
        case .wifi: "wifi"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .wired: "cable.connector"
        case .other: "network"
        case .none: "wifi.slash"
        }
    }
}

// MARK: - Metrics

private struct MetricsGrid: View {
    let monitor: MeetMonitor

    var body: some View {
        let s = monitor.stats
        let ready = monitor.isRunning && !monitor.isMeasuring
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(title: "Delay", value: ready ? s.latencyMs.map { "\(Int($0)) ms" } : nil,
                       level: ready ? s.latencyMs.map(Grader.latency) : nil, hint: "under 150 ms")
            MetricTile(title: "Jitter", value: ready ? s.jitterMs.map { "\(Int($0)) ms" } : nil,
                       level: ready ? s.jitterMs.map(Grader.jitter) : nil, hint: "under 30 ms")
            MetricTile(title: "Packet loss", value: ready ? String(format: "%.0f%%", s.lossPercent) : nil,
                       level: ready ? Grader.loss(s.lossPercent) : nil, hint: "under 2%")
            MetricTile(title: "Download", value: monitor.downloadMbps.map { String(format: "%.1f Mbps", $0) },
                       level: monitor.downloadMbps.map(Grader.download), hint: "3.2+ Mbps for HD",
                       busy: monitor.isSpeedTesting && monitor.downloadMbps == nil)
            MetricTile(title: "Upload", value: monitor.uploadMbps.map { String(format: "%.1f Mbps", $0) },
                       level: monitor.uploadMbps.map(Grader.upload), hint: "2.6+ Mbps for HD",
                       busy: monitor.isSpeedTesting && monitor.uploadMbps == nil)
            MetricTile(title: "Last speed test",
                       value: monitor.lastSpeedTest.map { $0.formatted(date: .omitted, time: .shortened) },
                       level: nil, hint: "every \(Int(monitor.speedTestEvery / 60)) min",
                       busy: monitor.isSpeedTesting)
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String?
    let level: Level?
    let hint: String
    var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let level {
                    Circle().fill(level.color).frame(width: 10, height: 10)
                }
            }
            if busy {
                ProgressView().frame(height: 28)
            } else {
                Text(value ?? "—")
                    .font(.title2.bold().monospacedDigit())
                    .frame(height: 28)
            }
            Text(hint).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LatencyChart: View {
    let pings: [PingPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Delay – last 2 minutes").font(.subheadline).foregroundStyle(.secondary)
            Chart {
                RuleMark(y: .value("Good limit", 150))
                    .foregroundStyle(.orange.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ForEach(pings) { p in
                    if let ms = p.ms {
                        LineMark(x: .value("Time", p.date), y: .value("ms", min(ms, 500)))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(.blue)
                    } else {
                        PointMark(x: .value("Time", p.date), y: .value("ms", 500))
                            .foregroundStyle(.red)
                            .symbolSize(20)
                    }
                }
            }
            .chartYScale(domain: 0...500)
            .chartXAxis(.hidden)
            .frame(height: 140)
            Text("Red dots are lost packets.").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ReasonsCard: View {
    let reasons: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("What's wrong", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(reasons, id: \.self) { Text("• \($0)") }
            Divider()
            Text("Tips: move closer to the router, pause downloads and streaming on other devices, or turn off your camera in Meet to keep the audio clear.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Controls

private struct Controls: View {
    let monitor: MeetMonitor

    var body: some View {
        HStack(spacing: 12) {
            Button {
                monitor.isRunning ? monitor.stop() : monitor.start()
            } label: {
                Label(monitor.isRunning ? "Stop" : "Start",
                      systemImage: monitor.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(monitor.isRunning ? .red : .blue)

            Button {
                Task { await monitor.runSpeedTest() }
            } label: {
                Label("Speed test", systemImage: "speedometer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(monitor.isSpeedTesting || monitor.link == .none)
        }
        .controlSize(.large)
    }
}

private struct SettingsCard: View {
    @Bindable var monitor: MeetMonitor

    var body: some View {
        VStack(spacing: 12) {
            Toggle("Alert me when quality drops", isOn: $monitor.alertsEnabled)
            Picker("Speed test", selection: $monitor.speedTestEvery) {
                Text("Every 1 min").tag(TimeInterval(60))
                Text("Every 2 min").tag(TimeInterval(120))
                Text("Every 5 min").tag(TimeInterval(300))
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}
