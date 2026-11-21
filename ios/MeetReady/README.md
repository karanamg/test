# MeetReady – is my Wi-Fi good enough for a Google Meet video call?

An iPhone app (SwiftUI, iOS 17+) that keeps checking your connection and tells you, in plain words,
whether it will hold up for a Google Meet video call. If the quality drops, or Wi-Fi disappears, it alerts you.

## What it shows

- **A verdict:** Excellent / Good / Fair / Poor / No connection, plus what that means for a call
  (for example "Audio is fine. Video may drop to low quality.").
- **Connection type:** Wi-Fi, Cellular or none, and whether Low Data Mode is on.
- **Live metrics,** each with a coloured dot:
  | Metric | Measured how | "Good" threshold |
  |---|---|---|
  | Delay (latency) | HEAD request to `gstatic.com/generate_204` every second, median of the last 30 | < 150 ms |
  | Jitter | Average change between pings in a row | < 30 ms |
  | Packet loss | Pings with no answer within 2 s | < 2 % |
  | Download | 4 MB from Cloudflare's speed test, every 1, 2 or 5 min | ≥ 3.2 Mbps (Meet HD) |
  | Upload | 2 MB to Cloudflare's speed test | ≥ 2.6 Mbps (Meet HD) |
- **A 2-minute delay chart** with lost packets marked in red.
- **"What's wrong" tips** that name the metric causing the problem.

## Alerts
- A notification and a haptic buzz when quality stays at Fair or worse for about 5 seconds
  (a single slow ping doesn't set it off).
- A notification when Wi-Fi drops or you switch to cellular, and when quality is good again.
- The screen stays awake while monitoring is on.

## Why there are no Wi-Fi "bars"
iOS does not let App Store apps read the Wi-Fi signal strength (RSSI). The app measures the things that
actually decide call quality instead. A strong signal on a busy network still gives a bad call, and these
numbers catch that.

## Limitation
iOS pauses apps in the background. MeetReady keeps testing while it is on screen, so use it **before joining**
and between calls, or run it on a second device next to you. It cannot keep testing while the Meet app is in front.

## Build and run (needs a Mac with Xcode 15+)
```bash
brew install xcodegen
cd ios/MeetReady
xcodegen            # creates MeetReady.xcodeproj
open MeetReady.xcodeproj
```
In Xcode, pick your Apple ID team under *Signing & Capabilities* (a free account is enough),
plug in your iPhone, and press **Run**. Allow notifications when asked.

To use your own bundle ID, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.

## Files
- `Sources/MeetMonitor.swift` – Wi-Fi/path watcher, ping loop, speed tests, alerts
- `Sources/Probe.swift` – the network measurements
- `Sources/Assessment.swift` – thresholds and the verdict
- `Sources/ContentView.swift` – the UI
