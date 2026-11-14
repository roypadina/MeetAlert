import Foundation
import XCTest
@testable import MeetAlert

final class SupportPromptTests: XCTestCase {
    private let day = SupportPromptState.day
    private let install = Date(timeIntervalSince1970: 1_794_528_000)  // 2026-11-13, a Friday (UTC)

    private func mayAsk(_ s: SupportPromptState, day d: Double, caught: Int = 50, version: String = "1.9.3") -> Bool {
        s.mayAsk(now: install.addingTimeInterval(d * day), installDate: install, meetingsCaught: caught, appVersion: version)
    }

    func testFirstAskNeedsSevenDaysAndMoreThan32Meetings() {
        let s = SupportPromptState()
        XCTAssertFalse(mayAsk(s, day: 6.9))
        XCTAssertFalse(mayAsk(s, day: 30, caught: 32), "never at 32 or fewer, however long installed")
        XCTAssertTrue(mayAsk(s, day: 7, caught: 33))
    }

    func testSnoozeHidesFourteenDays() {
        var s = SupportPromptState()
        s.record(.snooze, now: install.addingTimeInterval(10 * day), appVersion: "1.9.3")
        XCTAssertFalse(mayAsk(s, day: 23.9))
        XCTAssertTrue(mayAsk(s, day: 24))
    }

    func testSupportQuietFor180Days() {
        var s = SupportPromptState()
        s.record(.support, now: install.addingTimeInterval(10 * day), appVersion: "1.9.3")
        XCTAssertFalse(mayAsk(s, day: 189))
        XCTAssertTrue(mayAsk(s, day: 190))
    }

    func testNeverLastsUntilNextMajorAndNinetyDays() {
        var s = SupportPromptState()
        s.record(.never, now: install.addingTimeInterval(10 * day), appVersion: "1.9.3")
        XCTAssertFalse(mayAsk(s, day: 300, version: "1.10.0"), "a feature release must not undo 'never'")
        XCTAssertFalse(mayAsk(s, day: 50, version: "2.0.0"), "a major release within 90 days must not undo it")
        XCTAssertTrue(mayAsk(s, day: 100, version: "2.0.0"))
    }

    func testAtMostThreeAsksPerRolling365Days() {
        var s = SupportPromptState()
        for d in [10.0, 40, 70] { s.recordShown(install.addingTimeInterval(d * day)) }
        XCTAssertFalse(mayAsk(s, day: 300))
        XCTAssertTrue(mayAsk(s, day: 376), "the first ask has rolled out of the window")
    }

    func testOldStateWithoutSupportKeysStillDecodes() throws {
        let json = #"{"alertedKeys":["x|1@5"],"lastAgendaDay":"2026-11-12","supportPrompt":{"shownAt":[]}}"#
        let p = try JSONDecoder().decode(Store.Persisted.self, from: Data(json.utf8))
        XCTAssertEqual(p.alertedKeys, ["x|1@5"], "new keys must not wipe the existing state")
        XCTAssertEqual(p.meetingsCaught, 0)
        XCTAssertNil(p.installDate)
        XCTAssertEqual(p.supportPrompt, SupportPromptState())
    }

    /// 10 meetings/week, a release every 4 days (every 3rd a feature release, 2.0.0 at day 240),
    /// user snoozes twice then says never → 3 asks in year 1; the first once 33 meetings are caught (day 24).
    func testYearOnePacingMatchesThePlayground() {
        var s = SupportPromptState()
        var version = [1, 9, 3], releases = 0, caught = 0
        var asks: [Int] = []
        let cal = Calendar(identifier: .gregorian)
        for d in 0..<365 {
            if d > 0, d % 4 == 0 {
                releases += 1
                if d >= 240, version[0] == 1 { version = [2, 0, 0] }
                else if releases % 3 == 0 { version = [version[0], version[1] + 1, 0] }
                else { version[2] += 1 }
            }
            let now = install.addingTimeInterval(Double(d) * day)
            var utc = cal; utc.timeZone = TimeZone(identifier: "UTC")!
            guard !utc.isDateInWeekend(now) else { continue }
            caught += 2
            let v = version.map(String.init).joined(separator: ".")
            guard s.mayAsk(now: now, installDate: install, meetingsCaught: caught, appVersion: v) else { continue }
            s.recordShown(now)
            s.record(asks.count < 2 ? .snooze : .never, now: now, appVersion: v)
            asks.append(d)
        }
        XCTAssertEqual(asks.count, 3)
        XCTAssertEqual(asks.first, 24)
    }
}
