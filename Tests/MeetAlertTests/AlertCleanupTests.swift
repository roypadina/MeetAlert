import Foundation
import XCTest
@testable import MeetAlert

@MainActor
final class AlertCleanupTests: XCTestCase {
    private func meeting(_ id: String, start: Date = Date().addingTimeInterval(600),
                         series: String? = nil) -> Store.Meeting {
        Store.Meeting(key: "\(id)|\(Int(start.timeIntervalSince1970))", title: "Synthetic meeting",
                      start: start, end: start.addingTimeInterval(1800), hasPhysicalLocation: false,
                      joinURL: nil, seriesId: series, calendarTitle: "Test", calendarColor: nil)
    }

    private func withStore(state: Store.Persisted = Store.Persisted(),
                           tasks: [String: Task<Void, Never>] = [:],
                           _ body: (Store, URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            for task in tasks.values { task.cancel() }
            try? FileManager.default.removeItem(at: dir)
        }
        let store = Store(configDir: dir, persisted: state, escalationTasks: tasks)
        // Ignore refreshes the menu through tick(); keep that refresh away from EventKit.
        store.calendarAccessDenied = true
        try body(store, dir.appendingPathComponent("state.json"))
    }

    private func savedState(_ url: URL) throws -> Store.Persisted {
        try JSONDecoder().decode(Store.Persisted.self, from: Data(contentsOf: url))
    }

    private func pendingTask() -> Task<Void, Never> {
        Task { try? await Task.sleep(for: .seconds(3600)) }
    }

    func testDismissClearsAllOffsetsButPreservesOtherOccurrences() throws {
        let m = meeting("series", series: "series")
        let next = meeting("series", start: m.start.addingTimeInterval(3600), series: "series")
        let other = meeting("other", start: m.start)
        let selected = "\(m.key)@3", reShown = "\(m.key)@0", taskOnly = "\(m.key)@10"
        let otherKey = "\(other.key)@3", nextKey = "\(next.key)@3"
        let selectedTask = pendingTask(), hiddenTask = pendingTask(), otherTask = pendingTask()
        var state = Store.Persisted()
        state.alertedKeys = [selected, reShown, taskOnly]
        state.snoozedUntil = ["\(m.key)@30": m.start, otherKey: other.start, nextKey: next.start]

        try withStore(state: state, tasks: [selected: selectedTask, taskOnly: hiddenTask, otherKey: otherTask]) { store, url in
            store.showingAlerts = [(selected, m), (reShown, m), (otherKey, other), (nextKey, next)]
            store.ack(selected)

            XCTAssertEqual(Set(store.showingAlerts.map(\.key)), [otherKey, nextKey])
            XCTAssertTrue(selectedTask.isCancelled)
            XCTAssertTrue(hiddenTask.isCancelled)
            XCTAssertFalse(otherTask.isCancelled)
            let saved = try savedState(url)
            XCTAssertTrue(saved.alertedKeys.contains("\(m.key)@dismissed"))
            XCTAssertFalse(saved.alertedKeys.contains("\(next.key)@dismissed"))
            XCTAssertEqual(saved.snoozedUntil, [otherKey: other.start, nextKey: next.start])
        }
    }

    func testIgnoreOccurrenceClearsTasklessPanelsAndPendingSnoozes() throws {
        let m = meeting("series", series: "series")
        let next = meeting("series", start: m.start.addingTimeInterval(3600), series: "series")
        let panelKey = "\(m.key)@3", taskKey = "\(m.key)@0", nextKey = "\(next.key)@3"
        let task = pendingTask(), nextTask = pendingTask()
        var state = Store.Persisted()
        state.snoozedUntil = ["\(m.key)@10": m.start, nextKey: next.start]

        try withStore(state: state, tasks: [taskKey: task, nextKey: nextTask]) { store, url in
            store.showingAlerts = [(panelKey, m), (nextKey, next)]
            store.ignoreOccurrence(m)

            XCTAssertEqual(store.showingAlerts.map(\.key), [nextKey])
            XCTAssertTrue(task.isCancelled)
            XCTAssertFalse(nextTask.isCancelled)
            let saved = try savedState(url)
            XCTAssertEqual(saved.ignoredKeys, [m.key])
            XCTAssertTrue(saved.ignoredSeriesIds.isEmpty)
            XCTAssertEqual(saved.snoozedUntil, [nextKey: next.start])
        }
    }

    func testIgnoreSeriesClearsEveryOccurrenceIncludingSnoozedOnlyOnes() throws {
        let m = meeting("series", series: "series")
        let next = meeting("series", start: m.start.addingTimeInterval(3600), series: "series")
        let later = meeting("series", start: m.start.addingTimeInterval(7200), series: "series")
        let other = meeting("series-other", start: m.start, series: "series-other")
        let selected = "\(m.key)@3", nextKey = "\(next.key)@0", laterKey = "\(later.key)@3"
        let otherKey = "\(other.key)@3"
        let selectedTask = pendingTask(), nextTask = pendingTask(), otherTask = pendingTask()
        var state = Store.Persisted()
        state.snoozedUntil = [selected: m.start, laterKey: later.start, otherKey: other.start]

        try withStore(state: state, tasks: [selected: selectedTask, nextKey: nextTask, otherKey: otherTask]) { store, url in
            store.showingAlerts = [(selected, m), ("\(next.key)@3", next), (otherKey, other)]
            store.ignoreForever(m)

            XCTAssertEqual(store.showingAlerts.map(\.key), [otherKey])
            XCTAssertTrue(selectedTask.isCancelled)
            XCTAssertTrue(nextTask.isCancelled)
            XCTAssertFalse(otherTask.isCancelled)
            let saved = try savedState(url)
            XCTAssertEqual(saved.ignoredSeriesIds, ["series"])
            XCTAssertEqual(saved.snoozedUntil, [otherKey: other.start])
        }
    }

    func testIgnoreForeverForOneOffUsesOccurrenceCleanup() throws {
        let m = meeting("one-off")
        let key = "\(m.key)@3"
        try withStore { store, url in
            store.showingAlerts = [(key, m)]
            store.ignoreForever(m)
            XCTAssertTrue(store.showingAlerts.isEmpty)
            XCTAssertEqual(try savedState(url).ignoredKeys, [m.key])
        }
    }

    func testSnoozeOnlyStopsSelectedOffset() throws {
        let m = meeting("meeting")
        let key = "\(m.key)@3", sibling = "\(m.key)@0"
        let task = pendingTask(), siblingTask = pendingTask()
        try withStore(tasks: [key: task, sibling: siblingTask]) { store, url in
            store.showingAlerts = [(key, m), (sibling, m)]
            let before = Date()
            store.snooze(m, alertKey: key, minutes: 1)

            XCTAssertEqual(store.showingAlerts.map(\.key), [sibling])
            XCTAssertTrue(task.isCancelled)
            XCTAssertFalse(siblingTask.isCancelled)
            let saved = try savedState(url)
            let due = try XCTUnwrap(saved.snoozedUntil[key])
            XCTAssertGreaterThanOrEqual(due, before.addingTimeInterval(60))
            XCTAssertLessThanOrEqual(due, Date().addingTimeInterval(60))
            XCTAssertFalse(saved.alertedKeys.contains("\(m.key)@dismissed"))
        }
    }

    func testSnoozeUntilStartOnlyStopsSelectedOffset() throws {
        let m = meeting("meeting")
        let key = "\(m.key)@3", sibling = "\(m.key)@0"
        let task = pendingTask(), siblingTask = pendingTask()
        try withStore(tasks: [key: task, sibling: siblingTask]) { store, url in
            store.showingAlerts = [(key, m), (sibling, m)]
            store.snoozeUntilStart(m, alertKey: key)

            XCTAssertEqual(store.showingAlerts.map(\.key), [sibling])
            XCTAssertTrue(task.isCancelled)
            XCTAssertFalse(siblingTask.isCancelled)
            let saved = try savedState(url)
            XCTAssertEqual(saved.snoozedUntil[key], m.start)
            XCTAssertFalse(saved.alertedKeys.contains("\(m.key)@dismissed"))
        }
    }
    func testNewOffsetReplacesEarlierPopupAndItsEscalation() throws {
        let m = meeting("series", series: "series")
        let next = meeting("series", start: m.start.addingTimeInterval(3600), series: "series")
        let earlier = "\(m.key)@3", current = "\(m.key)@0", nextKey = "\(next.key)@3"
        let earlierTask = pendingTask(), nextTask = pendingTask()
        var state = Store.Persisted()
        state.snoozedUntil = [earlier: m.start, nextKey: next.start]
        try withStore(state: state, tasks: [earlier: earlierTask, nextKey: nextTask]) { store, url in
            store.showingAlerts = [(earlier, m), (nextKey, next)]
            XCTAssertTrue(store.preparePanel(m, alertKey: current, resumingSnooze: false))
            XCTAssertEqual(Set(store.showingAlerts.map(\.key)), [current, nextKey])
            XCTAssertTrue(earlierTask.isCancelled)
            XCTAssertFalse(nextTask.isCancelled)
            let saved = try savedState(url)
            XCTAssertEqual(saved.snoozedUntil, [nextKey: next.start])
            XCTAssertFalse(saved.alertedKeys.contains("\(m.key)@dismissed"))
        }
    }

    func testSnoozeResumingDoesNotReplaceAnAlreadyVisibleReminder() throws {
        let m = meeting("meeting")
        let current = "\(m.key)@0", snoozed = "\(m.key)@3"
        let currentTask = pendingTask()
        try withStore(tasks: [current: currentTask]) { store, _ in
            store.showingAlerts = [(current, m)]
            XCTAssertFalse(store.preparePanel(m, alertKey: snoozed, resumingSnooze: true))
            XCTAssertEqual(store.showingAlerts.map(\.key), [current])
            XCTAssertFalse(currentTask.isCancelled)
        }
    }

    func testRepeatedPresentationDoesNotDuplicateOrCancelCurrentReminder() throws {
        let m = meeting("meeting")
        let key = "\(m.key)@0"
        let task = pendingTask()
        try withStore(tasks: [key: task]) { store, _ in
            store.showingAlerts = [(key, m)]
            XCTAssertFalse(store.preparePanel(m, alertKey: key, resumingSnooze: false))
            XCTAssertEqual(store.showingAlerts.map(\.key), [key])
            XCTAssertFalse(task.isCancelled)
        }
    }

    func testDifferentMeetingsWithSameTitleStillGetSeparatePopups() throws {
        let a = meeting("a"), b = meeting("b")
        try withStore { store, _ in
            XCTAssertTrue(store.preparePanel(a, alertKey: "\(a.key)@3", resumingSnooze: true))
            XCTAssertTrue(store.preparePanel(b, alertKey: "\(b.key)@3", resumingSnooze: true))
            XCTAssertEqual(store.showingAlerts.count, 2)
        }
    }

    func testOffsetDueWhenASnoozeEndsOpensOnlyTheNewPopup() throws {
        let m = meeting("meeting")
        let earlier = "\(m.key)@3", current = "\(m.key)@0"
        var state = Store.Persisted()
        state.alertedKeys = [earlier]
        state.snoozedUntil = [earlier: m.start]  // Snooze 5m on the 3-min alert is capped to the start
        try withStore(state: state) { store, url in
            var shown: [String] = []
            store.presentPanelForTesting = { shown.append($0) }
            store.processAlerts(m, now: m.start)
            XCTAssertEqual(shown, [current])  // the snoozed popup never reopens just to be replaced
            XCTAssertEqual(store.showingAlerts.map(\.key), [current])
            XCTAssertTrue(try savedState(url).snoozedUntil.isEmpty)
        }
    }

    func testOccurrenceTokensCoverEveryOffsetOfThatOccurrenceOnly() throws {
        let m = meeting("series", series: "series")
        let next = meeting("series", start: m.start.addingTimeInterval(3600), series: "series")
        try withStore { store, _ in
            XCTAssertEqual(store.occurrenceTokens(m), [Store.hashToken("\(m.key)@3"), Store.hashToken("\(m.key)@0")])
            XCTAssertTrue(store.occurrenceTokens(m).isDisjoint(with: store.occurrenceTokens(next)))
        }
    }

    func testAutoDismissAtEndCancelsAllOffsetsAndPreservesOtherMeetings() throws {
        let m = meeting("series", series: "series")
        let next = meeting("series", start: m.start.addingTimeInterval(3600), series: "series")
        let key = "\(m.key)@3", nextKey = "\(next.key)@3"
        let task = pendingTask(), nextTask = pendingTask()
        var state = Store.Persisted()
        state.alertedKeys = [key]
        state.snoozedUntil = ["\(m.key)@0": m.end.addingTimeInterval(60), nextKey: next.start]
        try withStore(state: state, tasks: [key: task, nextKey: nextTask]) { store, url in
            store.showingAlerts = [(key, m), (nextKey, next)]
            store.dismissExpiredAlerts(meetings: [m, next], now: m.end.addingTimeInterval(-1))
            XCTAssertEqual(store.showingAlerts.count, 2)
            XCTAssertFalse(task.isCancelled)
            store.dismissExpiredAlerts(meetings: [m, next], now: m.end)
            XCTAssertEqual(store.showingAlerts.map(\.key), [nextKey])
            XCTAssertTrue(task.isCancelled)
            XCTAssertFalse(nextTask.isCancelled)
            let saved = try savedState(url)
            XCTAssertEqual(saved.snoozedUntil, [nextKey: next.start])
            XCTAssertTrue(saved.alertedKeys.contains("\(m.key)@dismissed"))
            XCTAssertFalse(saved.alertedKeys.contains("\(next.key)@dismissed"))
        }
    }

    func testWakeCleanupClosesTasklessAlertOutsideCalendarQuery() throws {
        let m = meeting("old", start: Date().addingTimeInterval(-4 * 3600))
        try withStore { store, _ in
            store.showingAlerts = [("\(m.key)@0", m)]
            // tick() must sweep visible windows even when upcoming() no longer returns the event.
            store.tick()
            XCTAssertTrue(store.showingAlerts.isEmpty)
        }
    }

    func testRefreshedMeetingEndExtendsVisibleAlert() throws {
        let m = meeting("extended")
        let extended = Store.Meeting(key: m.key, title: m.title, start: m.start,
                                    end: m.end.addingTimeInterval(3600), hasPhysicalLocation: false,
                                    joinURL: nil, seriesId: nil, calendarTitle: "Test", calendarColor: nil)
        try withStore { store, _ in
            store.showingAlerts = [("\(m.key)@0", m)]
            store.dismissExpiredAlerts(meetings: [extended], now: m.end)
            XCTAssertEqual(store.showingAlerts.count, 1)
            store.dismissExpiredAlerts(meetings: [], now: m.end.addingTimeInterval(60))
            XCTAssertEqual(store.showingAlerts.count, 1)  // retain refreshed dates if access disappears
            store.dismissExpiredAlerts(meetings: [], now: extended.end)
            XCTAssertTrue(store.showingAlerts.isEmpty)
        }
    }

    func testCustomTimeoutUsesMeetingStartAndDoesNotRestartForLaterOffset() throws {
        let m = meeting("custom")
        try withStore { store, _ in
            store.config.autoDismiss = .afterStart
            store.config.autoDismissMinutes = 5
            let key = "\(m.key)@-4"
            store.showingAlerts = [(key, m)]
            store.dismissExpiredAlerts(meetings: [], now: m.start.addingTimeInterval(299))
            XCTAssertEqual(store.showingAlerts.map(\.key), [key])
            store.dismissExpiredAlerts(meetings: [], now: m.start.addingTimeInterval(300))
            XCTAssertTrue(store.showingAlerts.isEmpty)
        }
    }

    func testExpiredRestoredSnoozeNeverPresentsOrRearms() throws {
        let m = meeting("snoozed")
        let key = "\(m.key)@3"
        var state = Store.Persisted()
        state.alertedKeys = [key]
        state.snoozedUntil = [key: m.start.addingTimeInterval(301)]
        try withStore(state: state) { store, url in
            store.config.autoDismiss = .afterStart
            store.config.autoDismissMinutes = 5
            store.presentPanelForTesting = { _ in XCTFail("An expired snooze must not reopen") }
            store.processAlerts(m, now: m.start.addingTimeInterval(301))
            XCTAssertTrue(store.showingAlerts.isEmpty)
            let saved = try savedState(url)
            XCTAssertTrue(saved.snoozedUntil.isEmpty)
            XCTAssertTrue(saved.alertedKeys.contains("\(m.key)@dismissed"))
            XCTAssertEqual(saved.meetingsCaught, 0)
        }
    }

    func testCatchUpDoesNotFireAfterAutoDismissDeadline() throws {
        let m = meeting("catch-up")
        try withStore { store, _ in
            store.config.autoDismiss = .afterStart
            store.config.autoDismissMinutes = 5
            store.config.lateAlertMinutes = 30
            store.presentPanelForTesting = { _ in XCTFail("Catch-up must respect auto-dismiss") }
            store.processAlerts(m, now: m.start.addingTimeInterval(300))
            XCTAssertTrue(store.showingAlerts.isEmpty)
        }
    }

    func testNeverKeepsOldAlertAndAllowsSnoozes() throws {
        let m = meeting("never")
        let key = "\(m.key)@0"
        var state = Store.Persisted()
        state.alertedKeys = [key]
        state.snoozedUntil = [key: m.end.addingTimeInterval(60)]
        try withStore(state: state) { store, _ in
            store.config.autoDismiss = .never
            var shown: [String] = []
            store.presentPanelForTesting = { shown.append($0) }
            store.processAlerts(m, now: m.end.addingTimeInterval(60))
            XCTAssertEqual(shown, [key])
            store.dismissExpiredAlerts(meetings: [], now: m.end.addingTimeInterval(3600))
            XCTAssertEqual(store.showingAlerts.map(\.key), [key])
        }
    }

    func testZeroLengthEventStillFiresAtStartAlert() throws {
        let start = Date().addingTimeInterval(600)
        let m = Store.Meeting(key: "zero|\(Int(start.timeIntervalSince1970))", title: "Synthetic meeting",
                              start: start, end: start, hasPhysicalLocation: false,
                              joinURL: nil, seriesId: nil, calendarTitle: "Test", calendarColor: nil)
        try withStore { store, _ in
            var shown: [String] = []
            store.presentPanelForTesting = { shown.append($0) }
            store.processAlerts(m, now: m.start)
            XCTAssertEqual(shown, ["\(m.key)@0"])
            store.dismissExpiredAlerts(meetings: [m], now: m.start.addingTimeInterval(299))
            XCTAssertEqual(store.showingAlerts.count, 1)
            store.dismissExpiredAlerts(meetings: [m], now: m.start.addingTimeInterval(300))
            XCTAssertTrue(store.showingAlerts.isEmpty)
        }
    }

    func testLateOffsetPastTimeoutStillFires() throws {
        let m = meeting("late-nag")
        try withStore { store, _ in
            store.config.alertMinutesBefore = [0, -10]
            store.config.autoDismiss = .afterStart
            store.config.autoDismissMinutes = 1
            var shown: [String] = []
            store.presentPanelForTesting = { shown.append($0) }
            store.processAlerts(m, now: m.start.addingTimeInterval(600))
            XCTAssertEqual(shown, ["\(m.key)@-10"])
            store.dismissExpiredAlerts(meetings: [m], now: m.start.addingTimeInterval(899))
            XCTAssertEqual(store.showingAlerts.count, 1)
            store.dismissExpiredAlerts(meetings: [m], now: m.start.addingTimeInterval(900))
            XCTAssertTrue(store.showingAlerts.isEmpty)
        }
    }

    func testChangingTimeoutAppliesToAlreadyOpenAlert() throws {
        let m = meeting("changed")
        try withStore { store, _ in
            store.config.autoDismiss = .never
            store.showingAlerts = [("\(m.key)@0", m)]
            store.dismissExpiredAlerts(meetings: [], now: m.end)
            XCTAssertEqual(store.showingAlerts.count, 1)
            store.config.autoDismiss = .meetingEnd
            store.dismissExpiredAlerts(meetings: [], now: m.end)
            XCTAssertTrue(store.showingAlerts.isEmpty)
        }
    }

}
