import Foundation

/// Network measurements. iOS does not let normal apps read the Wi-Fi signal
/// strength (RSSI), so we measure what actually decides call quality:
/// round-trip latency, jitter, packet loss and throughput.
enum Probe {
    /// Google's tiny "no content" endpoint – the same host family Meet uses.
    static let pingURL = URL(string: "https://www.gstatic.com/generate_204")!
    static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=4000000")!
    static let uploadURL = URL(string: "https://speed.cloudflare.com/__up")!

    /// One kept-alive connection so each ping measures a single round trip,
    /// not a fresh TCP + TLS handshake.
    static let pingSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 2
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static let speedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Returns round-trip time in milliseconds, or nil if the probe was lost.
    static func ping() async -> Double? {
        var request = URLRequest(url: pingURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2
        let start = ContinuousClock.now
        do {
            let (_, response) = try await pingSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
            return milliseconds(ContinuousClock.now - start)
        } catch {
            return nil
        }
    }

    /// Download speed in megabits per second.
    static func downloadMbps() async -> Double? {
        let start = ContinuousClock.now
        do {
            let (data, response) = try await speedSession.data(from: downloadURL)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
            return mbps(bytes: data.count, elapsed: ContinuousClock.now - start)
        } catch {
            return nil
        }
    }

    /// Upload speed in megabits per second.
    static func uploadMbps(bytes: Int = 2_000_000) async -> Double? {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let body = Data(count: bytes)
        let start = ContinuousClock.now
        do {
            let (_, response) = try await speedSession.upload(for: request, from: body)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
            return mbps(bytes: bytes, elapsed: ContinuousClock.now - start)
        } catch {
            return nil
        }
    }

    private static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    private static func mbps(bytes: Int, elapsed: Duration) -> Double? {
        let seconds = milliseconds(elapsed) / 1000
        guard seconds > 0 else { return nil }
        return Double(bytes) * 8 / seconds / 1_000_000
    }
}
