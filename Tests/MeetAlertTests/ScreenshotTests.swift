import AppKit
import SwiftUI
import XCTest
@testable import MeetAlert

/// Dev-only: renders the README screenshots offscreen with fake data.
/// `RENDER_SCREENSHOTS=1 MEETALERT_TEST=1 swift test --filter ScreenshotTests`
/// MEETALERT_TEST=1 points Store at ~/.config/meetalert-test, never the real config.
@MainActor
final class ScreenshotTests: XCTestCase {
    private func png<V: View>(_ view: V, size: CGSize, name: String, dark: Bool = false) throws {
        let host = NSHostingView(rootView: view.padding(0))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host  // never ordered front: nothing appears on screen
        host.layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/screenshots")
        try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("\(name).png"))
    }

    func testRender() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RENDER_SCREENSHOTS"] == "1", "dev-only")
        XCTAssertEqual(ProcessInfo.processInfo.environment["MEETALERT_TEST"], "1", "refusing to touch the real config")
        let soon = Date().addingTimeInterval(2 * 60 + 40)
        let m = Store.Meeting(key: "demo", title: "Design review", start: soon, end: soon.addingTimeInterval(1800),
                              hasPhysicalLocation: false, joinURL: URL(string: "https://meet.example.com/abc-defg-hij"),
                              seriesId: nil, calendarTitle: "Work", calendarColor: .systemBlue)
        func alert(_ s: Date, esc: Bool, title: String) -> AlertContent {
            let st = PanelState(); st.escalated = esc
            let meeting = Store.Meeting(key: "d", title: title, start: s, end: s.addingTimeInterval(1800), hasPhysicalLocation: false,
                                        joinURL: m.joinURL, seriesId: nil, calendarTitle: "Work", calendarColor: .systemBlue)
            return AlertContent(meeting: meeting, state: st, onJoin: {}, onSnooze1: {}, onSnooze5: {}, onSnoozeStart: {}, onIgnore: {}, onDismiss: {})
        }
        try png(alert(soon, esc: false, title: "Design review"), size: CGSize(width: 640, height: 168), name: "popup")
        let store = Store()
        store.config.ntfyTopic = "example-topic"
        store.config.agendaTime = 8 * 60
        try png(AlertsTab(store: store), size: CGSize(width: 520, height: 480), name: "settings-alerts")
        try png(PhoneTab(store: store), size: CGSize(width: 520, height: 400), name: "settings-phone")
    }
}
