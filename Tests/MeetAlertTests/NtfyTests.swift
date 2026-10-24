import XCTest
@testable import MeetAlert

final class NtfyTests: XCTestCase {
    private func cfg(token: String = "", fallback: String = "") -> Store.Config {
        var c = Store.Config()
        c.ntfyServer = "https://ntfy.example.com"
        c.ntfyTopic = "t"
        c.ntfyToken = token
        c.ntfyFallbackURL = fallback
        return c
    }

    func testAuthOnlyToSameOrigin() {
        let c = cfg(token: "tk_abc")
        XCTAssertEqual(Ntfy.authHeaders(for: URL(string: "https://ntfy.example.com/t/json")!, cfg: c)["Authorization"], "Bearer tk_abc")
        XCTAssertTrue(Ntfy.authHeaders(for: URL(string: "https://ntfy.sh/t")!, cfg: c).isEmpty)
        XCTAssertTrue(Ntfy.authHeaders(for: URL(string: "http://ntfy.example.com/t")!, cfg: c).isEmpty)
        XCTAssertTrue(Ntfy.authHeaders(for: URL(string: "https://ntfy.example.com:8443/t")!, cfg: c).isEmpty)
        XCTAssertTrue(Ntfy.authHeaders(for: URL(string: "https://ntfy.example.com/t")!, cfg: cfg()).isEmpty)  // no token
    }

    func testActionsCarryAuthOnlyWithToken() {
        let with = Ntfy.ackAction(token: "x", cfg: cfg(token: "tk_abc"))
        XCTAssertEqual(with.headers?["Authorization"], "Bearer tk_abc")
        XCTAssertEqual(with.headers?["X-Priority"], "min")  // echo silencing kept
        XCTAssertEqual(Ntfy.snoozeAction(token: "x", cfg: cfg(token: "tk_abc")).headers?["Authorization"], "Bearer tk_abc")
        XCTAssertNil(Ntfy.ackAction(token: "x", cfg: cfg()).headers?["Authorization"])
    }

    func testFooterAndFirstTag() {
        let p = Ntfy.payload(cfg: cfg(), topic: "t", flow: "escalation", event: "20261025-101500-7f3a", title: "T",
                             message: "Body", priority: 4, tags: ["alarm_clock"], actions: [], click: nil)
        XCTAssertEqual(p.tags, ["meetalert", "alarm_clock"])
        XCTAssertEqual(p.title, "T")
        let lines = p.message!.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Body")
        XCTAssertEqual(lines[1], "")
        XCTAssertTrue(lines[2].hasPrefix("sender: meetalert@"))
        XCTAssertEqual(Array(lines[3...5]), ["flow: escalation", "event: 20261025-101500-7f3a", "log: ~/Library/Logs/MeetAlert.log"])
        XCTAssertNotNil(Ntfy.eventID().range(of: #"^\d{8}-\d{6}-[0-9a-f]{4}$"#, options: .regularExpression))
    }

    func testAckDetectionIgnoresFooter() {
        let footer = Ntfy.footer(flow: "meeting-alert", event: "e")
        let alert = #"{"message":"Starts in 3 min\#(footer.replacingOccurrences(of: "\n", with: "\\n"))"}"#
        let ack = #"{"message":"meetack abc"}"#
        let snooze = #"{"message":"meetsnooze abc"}"#
        XCTAssertNil(Ntfy.ackOutcome(in: Data(alert.utf8), token: "abc"))
        XCTAssertEqual(Ntfy.ackOutcome(in: Data("\(alert)\n\(ack)".utf8), token: "abc"), .acked)
        XCTAssertEqual(Ntfy.ackOutcome(in: Data("\(alert)\n\(snooze)".utf8), token: "abc"), .snoozed)
        XCTAssertNil(Ntfy.ackOutcome(in: Data(ack.utf8), token: "other"))
    }

    func testFallbackDecision() {
        let fb = cfg(fallback: "https://ntfy.sh/pub-topic")
        XCTAssertTrue(Ntfy.shouldFallback(status: nil, cfg: fb))
        XCTAssertTrue(Ntfy.shouldFallback(status: 403, cfg: fb))
        XCTAssertTrue(Ntfy.shouldFallback(status: 502, cfg: fb))
        XCTAssertFalse(Ntfy.shouldFallback(status: 200, cfg: fb))
        XCTAssertFalse(Ntfy.shouldFallback(status: nil, cfg: cfg()))  // no fallback configured
        let t = Ntfy.fallbackTarget("https://ntfy.sh/pub-topic")
        XCTAssertEqual(t?.root.absoluteString, "https://ntfy.sh")
        XCTAssertEqual(t?.topic, "pub-topic")
        XCTAssertNil(Ntfy.fallbackTarget("not a url"))
    }

    func testFallbackMessageHasNoActionsNorAuth() throws {
        let c = cfg(token: "tk_abc", fallback: "https://ntfy.sh/pub-topic")
        let p = Ntfy.payload(cfg: c, topic: "pub-topic", flow: "escalation", event: "e", title: "T", message: "B",
                             priority: 5, tags: ["rotating_light"], actions: [], click: nil)
        let json = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        XCTAssertFalse(json.contains("actions"))
        XCTAssertFalse(json.contains("tk_abc"))
        XCTAssertTrue(json.contains("meetalert"))
        let fb = URL(string: "https://ntfy.sh")!
        XCTAssertTrue(Ntfy.authHeaders(for: fb, cfg: c).isEmpty)  // different origin: no Authorization
    }

    func testConfigBackCompat() throws {
        let old = #"{"ntfyServer":"https://ntfy.sh","ntfyTopic":"abc"}"#
        let c = try JSONDecoder().decode(Store.Config.self, from: Data(old.utf8))
        XCTAssertEqual(c.ntfyTopic, "abc")
        XCTAssertEqual(c.ntfyToken, "")
        XCTAssertEqual(c.ntfyFallbackURL, "")
        // secrets never reach config.json
        var s = c
        s.ntfyToken = "tk_secret"; s.ntfyFallbackURL = "https://ntfy.sh/secret-topic"
        let out = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        XCTAssertFalse(out.contains("tk_secret"))
        XCTAssertFalse(out.contains("secret-topic"))
        // no token: ntfy.sh users send nothing new
        XCTAssertTrue(Ntfy.authHeaders(for: URL(string: "https://ntfy.sh/abc")!, cfg: c).isEmpty)
    }
}
