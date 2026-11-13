import Foundation
import XCTest
@testable import MeetAlert

@MainActor
final class ConfigLoadingTests: XCTestCase {
    func testStartupCredentialsDoNotOverwriteSavedPreferences() throws {
        for token in ["", "synthetic-token"] {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("config.json")
            var saved = Store.Config()
            saved.alertMinutesBefore = [10, 2]
            saved.ignoreAllDay = false
            saved.calendarIds = ["synthetic-calendar"]
            saved.ntfyTopic = "synthetic-topic"
            try JSONEncoder().encode(saved).write(to: url)

            let store = Store(configDir: dir)
            let fallback = token.isEmpty ? "" : "https://example.com/synthetic-fallback"
            store.loadConfig(token: token, fallbackURL: fallback)
            var expected = saved
            expected.ntfyToken = token
            expected.ntfyFallbackURL = fallback
            XCTAssertEqual(store.config, expected)
            XCTAssertEqual(try JSONDecoder().decode(Store.Config.self, from: Data(contentsOf: url)), saved)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertNil(json["ntfyToken"])
            XCTAssertNil(json["ntfyFallbackURL"])
        }
    }
}
