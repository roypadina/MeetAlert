import AppKit
import CoreGraphics
import EventKit
import Foundation
import Observation
import ServiceManagement

// Private API, no public header. @_silgen_name would hard-link the symbol at load time — if it
// ever vanishes from a future macOS, the WHOLE APP fails to launch. Resolve it lazily via dlsym
// instead: missing symbol just means isAway() falls back to idle-only (screen lock untestable).
private typealias CGSessionCopyCurrentDictionaryFn = @convention(c) () -> CFDictionary?
private let cgSessionCopyCurrentDictionary: CGSessionCopyCurrentDictionaryFn? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSessionCopyCurrentDictionary") else { return nil }
    return unsafeBitCast(sym, to: CGSessionCopyCurrentDictionaryFn.self)
}()

private func isScreenLocked() -> Bool {
    guard let fn = cgSessionCopyCurrentDictionary,
          let session = fn() as? [String: Any] else { return false }
    return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
}

@Observable @MainActor
final class Store {
    struct Meeting: Identifiable {
        let key: String
        let title: String
        let start: Date
        let end: Date
        let hasPhysicalLocation: Bool
        let joinURL: URL?
        let seriesId: String?  // event identifier when the event recurs; nil for one-offs
        var id: String { key }
    }

    struct Config: Codable, Equatable {
        var alertMinutesBefore: [Int] = [3, 0]  // positive = before start, 0 = at start, negative = after start
        var lateAlertMinutes = 10  // fire a missed alert up to this long past its scheduled time (covers Google→macOS sync lag)
        var escalationSeconds = 120
        var awayIdleSeconds = 120  // idle (or screen-locked) this long → treat as away from the Mac
        var travelLeadMinutes = 30  // extra alert offset for meetings with a physical location
        var agendaTime: Int? = nil  // minutes since midnight to push today's agenda; nil = off
        var ignoreAllDay = true
        var ignoreKeywords: [String] = []
        var ntfyServer = "https://ntfy.sh"
        var ntfyTopic = ""  // empty = phone notifications disabled; set your private topic
        var calendarIds: [String]? = nil  // nil = all calendars

        private enum CodingKeys: String, CodingKey {
            case alertMinutesBefore, lateAlertMinutes, escalationSeconds, awayIdleSeconds, travelLeadMinutes,
                 agendaTime, ignoreAllDay, ignoreKeywords, ntfyServer, ntfyTopic, calendarIds
            case leadMinutes, agendaHour  // legacy keys, migrated in init(from:) below
        }

        init() {}

        // Tolerant decode: every field falls back to its default independently, so an old or
        // partial config.json never fails the whole struct (a failed decode used to silently
        // keep ALL defaults, losing things like ntfyTopic).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let before = try c.decodeIfPresent([Int].self, forKey: .alertMinutesBefore) {
                alertMinutesBefore = Self.normalized(before)
            } else if let legacy = try c.decodeIfPresent(Int.self, forKey: .leadMinutes) {
                alertMinutesBefore = Self.normalized([legacy])
            } else {
                alertMinutesBefore = [3, 0]
            }
            lateAlertMinutes = try c.decodeIfPresent(Int.self, forKey: .lateAlertMinutes) ?? 10
            escalationSeconds = try c.decodeIfPresent(Int.self, forKey: .escalationSeconds) ?? 120
            awayIdleSeconds = try c.decodeIfPresent(Int.self, forKey: .awayIdleSeconds) ?? 120
            travelLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .travelLeadMinutes) ?? 30
            agendaTime = try c.decodeIfPresent(Int.self, forKey: .agendaTime)
                ?? (try c.decodeIfPresent(Int.self, forKey: .agendaHour)).map { $0 * 60 }  // legacy hour-only field
            ignoreAllDay = try c.decodeIfPresent(Bool.self, forKey: .ignoreAllDay) ?? true
            ignoreKeywords = try c.decodeIfPresent([String].self, forKey: .ignoreKeywords) ?? []
            ntfyServer = try c.decodeIfPresent(String.self, forKey: .ntfyServer) ?? "https://ntfy.sh"
            ntfyTopic = try c.decodeIfPresent(String.self, forKey: .ntfyTopic) ?? ""
            calendarIds = try c.decodeIfPresent([String].self, forKey: .calendarIds)
        }

        // Not private: SettingsView commits the alert-times field through the same normalization.
        static func normalized(_ minutes: [Int]) -> [Int] {
            let deduped = Array(Set(minutes)).sorted(by: >)
            return deduped.isEmpty ? [3] : deduped
        }

        // CodingKeys has a case with no stored property (leadMinutes, decode-only), which blocks
        // synthesis of encode(to:) too — so write it by hand. Same shape as before, no leadMinutes.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(alertMinutesBefore, forKey: .alertMinutesBefore)
            try c.encode(lateAlertMinutes, forKey: .lateAlertMinutes)
            try c.encode(escalationSeconds, forKey: .escalationSeconds)
            try c.encode(awayIdleSeconds, forKey: .awayIdleSeconds)
            try c.encode(travelLeadMinutes, forKey: .travelLeadMinutes)
            try c.encode(agendaTime, forKey: .agendaTime)
            try c.encode(ignoreAllDay, forKey: .ignoreAllDay)
            try c.encode(ignoreKeywords, forKey: .ignoreKeywords)
            try c.encode(ntfyServer, forKey: .ntfyServer)
            try c.encode(ntfyTopic, forKey: .ntfyTopic)
            try c.encode(calendarIds, forKey: .calendarIds)
        }
    }

    struct Persisted: Codable {
        var ignoredKeys: Set<String> = []
        var ignoredSeriesIds: Set<String> = []  // recurring series ignored whole (never pruned; tiny)
        var ignoredTitles: [String: String] = [:]  // key/seriesId → display label for the Settings list
        var alertedKeys: Set<String> = []  // "identifier|epoch@offset" — epoch used to prune >24h old
        var snoozedUntil: [String: Date] = [:]  // keyed by alertKey; survives a restart
        var lastAgendaDay: String = ""  // "yyyy-MM-dd" of the last morning-agenda push

        init() {}

        // Tolerant decode, same reasoning as Config: a synthesized decoder throws on ANY missing
        // key, and the caller's `try?` silently falls back to Persisted() — on upgrade, that wiped
        // every v1.0.0 user's alertedKeys/ignoredKeys the moment lastAgendaDay didn't exist yet,
        // and the very next saveState() overwrote state.json with the now-empty defaults for good.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ignoredKeys = try c.decodeIfPresent(Set<String>.self, forKey: .ignoredKeys) ?? []
            ignoredSeriesIds = try c.decodeIfPresent(Set<String>.self, forKey: .ignoredSeriesIds) ?? []
            ignoredTitles = try c.decodeIfPresent([String: String].self, forKey: .ignoredTitles) ?? [:]
            alertedKeys = try c.decodeIfPresent(Set<String>.self, forKey: .alertedKeys) ?? []
            snoozedUntil = try c.decodeIfPresent([String: Date].self, forKey: .snoozedUntil) ?? [:]
            lastAgendaDay = try c.decodeIfPresent(String.self, forKey: .lastAgendaDay) ?? ""
        }
    }

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/meetalert")
    static let configURL = configDir.appendingPathComponent("config.json")
    static let stateURL = configDir.appendingPathComponent("state.json")

    var menuBarText = ""
    var upcomingList: [Meeting] = []
    var calendarAccessDenied = false
    var calendarSelectionBroken = false  // calendarIds resolved to zero live calendars (e.g. account re-added, ids rotated)
    var lastPushFailed = false  // last ntfy publish attempt (with a topic configured) didn't succeed

    private let testMode = ProcessInfo.processInfo.environment["MEETALERT_TEST"] == "1"
    @ObservationIgnored private lazy var ekStore = EKEventStore()  // never touched in test mode
    var config = Config() { didSet { saveConfig() } }  // Settings GUI + config.json both write here
    private var persisted = Persisted()
    private var testMeetings: [Meeting] = []
    private var escalationTasks: [String: Task<Void, Never>] = [:]
    private var timer: Timer?
    private var accessResolved = false  // true once requestFullAccessToEvents has completed (either way)
    private var agendaSending = false  // in-flight guard: a publish slower than one 30s tick must not double-send
    private var activityToken: NSObjectProtocol?  // held for the app's lifetime so App Nap doesn't stall the timer

    /// Earliest snooze-until date across every offset of a meeting occurrence — for the menu's
    /// "Snoozed:" row, which only knows the meeting key, not which offset(s) are snoozed.
    func snoozedUntilDate(for meetingKey: String) -> Date? {
        persisted.snoozedUntil
            .filter { $0.key.hasPrefix("\(meetingKey)@") }
            .values
            .min()
    }

    func start() {
        loadConfigAndState()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 5  // let the system coalesce/defer slightly under App Nap instead of waking exactly on time
        activityToken = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "meeting alert scheduling")
        if testMode {
            scheduleTestMeeting()
            return
        }
        // Register for login exactly once, ever — re-checking `.enabled` on every launch meant a
        // user who removed it via System Settings got it silently re-added on the next launch.
        if !UserDefaults.standard.bool(forKey: "didRegisterLoginItem") {
            UserDefaults.standard.set(true, forKey: "didRegisterLoginItem")
            if SMAppService.mainApp.status != .enabled {
                try? SMAppService.mainApp.register()
            }
        }
        Task { await requestAccessAndTick() }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func requestAccessAndTick() async {
        do {
            calendarAccessDenied = !(try await ekStore.requestFullAccessToEvents())
        } catch {
            calendarAccessDenied = true
        }
        accessResolved = true
        tick()
    }

    private func scheduleTestMeeting() {
        Task {
            try? await Task.sleep(for: .seconds(10))
            let start = Date().addingTimeInterval(180)
            testMeetings = [Meeting(key: "test|\(Int(start.timeIntervalSince1970))",
                                     title: "[TEST] MeetAlert pipeline",
                                     start: start,
                                     end: start.addingTimeInterval(30 * 60),
                                     hasPhysicalLocation: false,
                                     joinURL: nil,
                                     seriesId: nil)]
            tick()
        }
    }

    /// The only scheduler: scan, update menu text, fire due meetings, re-show due snoozes.
    func tick() {
        loadConfig()
        let now = Date()
        let list = upcoming()
        // Menu bar + upcoming list show anything still in progress or ahead —
        // the fire loop below still needs the full list to catch offsets due in the past.
        let visible = list.filter { $0.end > now }
        upcomingList = Array(visible.prefix(4))
        let warningPrefix = (calendarSelectionBroken || lastPushFailed) ? "⚠︎ " : ""
        let noCalendarsSelected = config.calendarIds?.isEmpty == true
        menuBarText = calendarAccessDenied ? "⚠︎ no calendar access"
            : noCalendarsSelected ? "no calendars selected"
            : warningPrefix + menuBarTextFor(visible, now: now)

        for m in list {
            for offset in offsets(for: m) {
                let alertKey = "\(m.key)@\(offset)"
                if let due = persisted.snoozedUntil[alertKey], now >= due {
                    persisted.snoozedUntil.removeValue(forKey: alertKey)
                    saveState()
                    showPanel(m, alertKey: alertKey, token: nil)  // re-show only, no re-arm
                }
            }
            fireDueOffsets(m, now: now)
        }
        sendMorningAgenda()
    }

    /// Once a day, at or after agendaTime, push today's remaining schedule via ntfy (default priority,
    /// no ACK/escalation — informational only). Only runs once calendar access has actually resolved
    /// (not just defaulted to "not denied yet"), and only marks the day done once something either
    /// genuinely had nothing to send or the push actually succeeded — never burns the day's slot on
    /// a failed send.
    private func sendMorningAgenda() {
        guard let agendaTime = config.agendaTime, !testMode, accessResolved, !calendarAccessDenied, !agendaSending else { return }
        let now = Date()
        let cal = Calendar.current
        let minutesNow = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        guard minutesNow >= agendaTime else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: now)
        guard persisted.lastAgendaDay != today else { return }

        guard let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) else { return }
        let todays = applyIgnores(fetchMeetings(from: now, to: endOfDay)).sorted { $0.start < $1.start }
        guard !todays.isEmpty else {
            persisted.lastAgendaDay = today  // legitimately nothing to send today
            saveState()
            return
        }

        let fmt = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        var lines = ["\(todays.count) meetings today. First: \(fmt(todays[0].start)) \(todays[0].title)"]
        lines += todays.prefix(6).map { "\(fmt($0.start)) \($0.title)" }
        let cutoff = cal.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? endOfDay
        if let gap = largestGap(in: todays, before: cutoff) {
            lines.append("Largest free gap: \(fmt(gap.start))–\(fmt(gap.end)) (\(gap.minutes)m)")
        }
        let cfg = config
        agendaSending = true
        Task {
            let ok = await Ntfy.agenda(body: lines.joined(separator: "\n"), cfg: cfg)
            await MainActor.run {
                self.agendaSending = false
                self.lastPushFailed = !ok
                guard ok else { return }
                self.persisted.lastAgendaDay = today
                self.saveState()
            }
        }
    }

    /// Largest free gap strictly between two consecutive meetings (not before the first or after the
    /// last), capped at `cutoff`.
    private func largestGap(in meetings: [Meeting], before cutoff: Date) -> (start: Date, end: Date, minutes: Int)? {
        var best: (Date, Date)?
        for i in 0..<max(meetings.count - 1, 0) {
            let gapStart = meetings[i].end
            let gapEnd = min(meetings[i + 1].start, cutoff)
            guard gapEnd > gapStart else { continue }
            if best == nil || gapEnd.timeIntervalSince(gapStart) > best!.1.timeIntervalSince(best!.0) {
                best = (gapStart, gapEnd)
            }
        }
        guard let best else { return nil }
        return (best.0, best.1, Int(best.1.timeIntervalSince(best.0) / 60))
    }

    /// Configured offsets, plus one extra travel-lead offset for meetings with a physical location.
    private func offsets(for m: Meeting) -> [Int] {
        m.hasPhysicalLocation ? config.alertMinutesBefore + [config.travelLeadMinutes] : config.alertMinutesBefore
    }

    /// Offsets of the same meeting due-and-unfired in one tick (e.g. the event synced in late)
    /// collapse into ONE alert — the latest alertTime — with ALL their keys marked fired so the
    /// earlier ones never fire separately.
    private func fireDueOffsets(_ m: Meeting, now: Date) {
        // Dismissed/ACKed once → done with this occurrence entirely; no other offset fires.
        guard !persisted.alertedKeys.contains("\(m.key)@dismissed") else { return }
        // If a later-or-equal offset already fired (e.g. the user just added an earlier offset, or
        // a travel-lead offset, to a meeting that already alerted), don't insta-fire the earlier one
        // as "catch-up" — that already-passed alert is noise, not a missed alert.
        let latestFiredAlertTime = persisted.alertedKeys.compactMap { key -> Date? in
            guard key.hasPrefix("\(m.key)@"), let offsetStr = key.split(separator: "@").last, let offset = Int(offsetStr) else { return nil }
            return m.start.addingTimeInterval(-Double(offset * 60))
        }.max()

        let due = offsets(for: m).compactMap { offset -> (key: String, alertTime: Date)? in
            let key = "\(m.key)@\(offset)"
            guard !persisted.alertedKeys.contains(key) else { return nil }
            let alertTime = m.start.addingTimeInterval(-Double(offset * 60))
            if let latestFiredAlertTime, alertTime <= latestFiredAlertTime { return nil }
            guard now >= alertTime, now <= alertTime.addingTimeInterval(Double(config.lateAlertMinutes * 60)) else { return nil }
            return (key, alertTime)
        }
        guard let winner = due.max(by: { $0.alertTime < $1.alertTime }) else { return }
        persisted.alertedKeys.formUnion(due.map(\.key))
        saveState()
        fire(m, alertKey: winner.key)
    }

    private func upcoming() -> [Meeting] {
        let source: [Meeting]
        if testMode {
            source = testMeetings
        } else if calendarAccessDenied {
            source = []
        } else {
            let now = Date()
            // Lookback must reach the most-negative (latest, after-start) offset plus the catch-up window.
            let mostNegative = min(config.alertMinutesBefore.min() ?? 0, 0)
            let lookback = Double(abs(mostNegative) * 60 + config.lateAlertMinutes * 60)
            source = fetchMeetings(from: now.addingTimeInterval(-lookback), to: now.addingTimeInterval(12 * 3600))
        }
        return applyIgnores(source).sorted { $0.start < $1.start }
    }

    /// The single ignore gate — occurrence keys AND whole recurring series. Used by the fire-loop
    /// scan, the morning agenda (which previously skipped ignore filtering entirely), and the
    /// Settings pre-ignore picker.
    private func applyIgnores(_ list: [Meeting]) -> [Meeting] {
        list.filter { m in
            !persisted.ignoredKeys.contains(m.key)
                && (m.seriesId.map { !persisted.ignoredSeriesIds.contains($0) } ?? true)
        }
    }

    /// Every event calendar across every account/source. Used by Settings' calendar toggle (so
    /// unticking one calendar doesn't drop every other account's calendars from the selection) and
    /// as the fallback when a saved `calendarIds` no longer resolves to anything real.
    func allCalendarIds() -> [String] {
        guard !testMode, !calendarAccessDenied else { return [] }
        return ekStore.calendars(for: .event).map(\.calendarIdentifier)
    }

    /// Shared EventKit fetch + filter chain, used by both the fire-loop scan and the morning agenda.
    private func fetchMeetings(from start: Date, to end: Date) -> [Meeting] {
        let calendars: [EKCalendar]?
        if let ids = config.calendarIds {
            if ids.isEmpty {
                // calendarIds == [] is a DELIBERATE "watch nothing" (every toggle unticked) — not
                // the same as a stale/rotated selection. No fallback, no broken warning.
                calendarSelectionBroken = false
                calendars = []
            } else {
                let resolved = ekStore.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
                if resolved.isEmpty {
                    // Non-empty selection matches nothing real anymore (e.g. account re-added,
                    // identifiers rotated) — fall back to every calendar instead of going dead.
                    calendarSelectionBroken = true
                    calendars = nil
                } else {
                    calendarSelectionBroken = false
                    calendars = resolved  // partial resolve is fine — just use what matched
                }
            }
        } else {
            calendarSelectionBroken = false
            calendars = nil
        }
        let predicate = ekStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return ekStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .filter { !(config.ignoreAllDay && $0.isAllDay) }
            .filter { event in
                !config.ignoreKeywords.contains { (event.title ?? "").localizedCaseInsensitiveContains($0) }
            }
            .filter { event in
                !(event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } == true)
            }
            .map { event in
                let epoch = Int(event.startDate.timeIntervalSince1970)
                let location = event.location ?? ""
                return Meeting(key: "\(event.eventIdentifier ?? event.title ?? "untitled")|\(epoch)",
                               title: event.title ?? "(untitled)",
                               start: event.startDate,
                               end: event.endDate ?? event.startDate.addingTimeInterval(3600),
                               hasPhysicalLocation: !location.isEmpty && !location.contains("://"),
                               joinURL: Self.extractJoinURL(event),
                               seriesId: event.hasRecurrenceRules ? event.eventIdentifier : nil)
            }
    }

    private static let joinURLPattern = try! NSRegularExpression(pattern: #"https?://[^\s<>"]+"#)
    private static let joinURLHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com",
                                       "gotomeeting.com", "meet.jit.si", "chime.aws", "bluejeans.com", "ringcentral.com"]

    /// Scans event.url + location + notes (in that order) for the first URL whose host is a known
    /// video-call provider.
    private static func extractJoinURL(_ event: EKEvent) -> URL? {
        let text = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        let matches = joinURLPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let range = Range(match.range, in: text),
                  let url = URL(string: String(text[range])),
                  let host = url.host else { continue }
            if joinURLHosts.contains(where: { host.contains($0) }) { return url }
        }
        return nil
    }

    /// Calendars grouped by source, for the Settings calendar checklist. Empty in test mode or when access is denied.
    func calendarsBySource() -> [(title: String, calendars: [EKCalendar])] {
        guard !testMode, !calendarAccessDenied else { return [] }
        let grouped = Dictionary(grouping: ekStore.calendars(for: .event), by: { $0.source.sourceIdentifier })
        return grouped.values
            .compactMap { cals in cals.first.map { (title: $0.source.title, calendars: cals) } }
            .sorted { $0.title < $1.title }
    }

    private func menuBarTextFor(_ list: [Meeting], now: Date) -> String {
        guard let current = list.first else { return "" }
        if current.start <= now, now < current.end {
            let minsLeft = Int(ceil(current.end.timeIntervalSince(now) / 60))
            if let next = list.dropFirst().first, next.start.timeIntervalSince(now) <= 2 * 3600 {
                return "\(minsLeft)m left → \(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)"
            }
            return "\(minsLeft)m left · \(current.title)"
        }
        guard current.start.timeIntervalSince(now) <= 2 * 3600 else { return "" }
        let secondsLeft = Int(current.start.timeIntervalSince(now))
        if secondsLeft <= 0 { return "now \(current.title)" }
        return "\(Int(ceil(Double(secondsLeft) / 60)))m \(current.title)"
    }

    /// Away from the Mac (idle past awayIdleSeconds, or screen locked) → nobody's at the desk to
    /// see the desktop popup, so skip straight to urgent priority on the phone. Test mode has no
    /// real HID input at all, which would otherwise always read as "away" — force present instead
    /// so the headless pipeline keeps its deterministic today's-semantics behavior.
    private func isAway() -> Bool {
        if testMode { return false }
        if isScreenLocked() { return true }
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
        return idleSeconds > Double(config.awayIdleSeconds)
    }

    /// Short stable hash of the alertKey — NOT the meeting's start epoch. The old epoch-based token
    /// was shared across every offset of a meeting (an ACK for one killed another's escalation) and
    /// across different meetings that happened to start the same second (cross-meeting ACK/snooze).
    /// Hashing the full alertKey (which already embeds the calendar identifier + start epoch +
    /// offset) makes each alert's token unique to it. FNV-1a, 32-bit.
    private static func hashToken(_ s: String) -> String {
        var hash: UInt32 = 2166136261
        for byte in s.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return String(hash, radix: 16)
    }

    /// ntfy ack token is per-alertKey now (see hashToken) — an ACK/snooze only ever matches its own
    /// escalation loop, never a different offset or a different meeting.
    private func fire(_ m: Meeting, alertKey: String) {
        let token = Self.hashToken(alertKey)
        if testMode { emit("fired \(token)") }
        let away = isAway()
        showPanel(m, alertKey: alertKey, token: token)

        let since = Int(Date().timeIntervalSince1970)
        let cfg = config
        let testMode = testMode
        let maxUrgent = testMode ? 1 : 3  // repeating escalation, bounded
        let hardDeadline = m.start.addingTimeInterval(15 * 60)  // never escalate past this regardless of offset
        escalationTasks[alertKey] = Task {
            defer { Task { @MainActor in self.escalationTasks.removeValue(forKey: alertKey) } }
            for _ in 0..<maxUrgent {
                let deadline = min(Date().addingTimeInterval(Double(testMode ? 20 : cfg.escalationSeconds)), hardDeadline)
                guard deadline > Date() else { break }
                let outcome = await Ntfy.waitForAck(token: token, since: since, deadline: deadline, cfg: cfg)
                guard !Task.isCancelled else { return }
                switch outcome {
                case .acked:
                    await MainActor.run { self.ack(alertKey) }
                    return
                case .snoozed:
                    await MainActor.run { self.snooze(m, alertKey: alertKey, minutes: 5) }
                    return
                case .timedOut:
                    let ok = await Ntfy.urgent(m, token: token, cfg: cfg, test: testMode)
                    await MainActor.run { self.lastPushFailed = !ok }
                    if testMode { await MainActor.run { self.emit("escalated \(token)") } }
                }
            }
        }
        // Away → skip the grace window nobody at the desk will use; go out urgent immediately (still with the ACK action).
        Task {
            let ok = await Ntfy.alert(m, token: token, cfg: cfg, test: testMode, priority: away ? "urgent" : "high")
            await MainActor.run { self.lastPushFailed = !ok }
        }
    }

    /// token == nil means "re-show a snoozed panel" (no ntfy, no escalation).
    private func showPanel(_ m: Meeting, alertKey: String, token: String?) {
        AlertPanel.show(m, alertKey: alertKey,
            onAck: { [weak self] in self?.ack(alertKey) },
            onSnooze: { [weak self] minutes in self?.snooze(m, alertKey: alertKey, minutes: minutes) },
            onSnoozeStart: { [weak self] in self?.snoozeUntilStart(m, alertKey: alertKey) },
            onIgnore: { [weak self] in self?.ignoreForever(m) })
    }

    /// Settings' "Send test push" button.
    func sendTestPush() async -> Bool {
        let ok = await Ntfy.test(cfg: config)
        lastPushFailed = !ok
        return ok
    }

    /// Cancels escalation and closes the desktop panel for one alertKey. Shared by ack (final)
    /// and snooze (alert comes back later), so it must NOT mark the occurrence dismissed itself.
    private func stopAlert(_ key: String) {
        escalationTasks[key]?.cancel()
        escalationTasks.removeValue(forKey: key)
        AlertPanel.dismiss(key: key)  // a phone ACK/snooze closes the desktop panel too, not just escalation
        if testMode { emit("acked \(Self.hashToken(key))") }
    }

    /// Dismiss/ACK (desktop button, phone ACK, or Join) = done with this meeting occurrence:
    /// every remaining offset is suppressed and pending snoozes for it are dropped.
    func ack(_ key: String) {
        stopAlert(key)
        guard let at = key.lastIndex(of: "@") else { return }
        let meetingKey = String(key[..<at])
        persisted.alertedKeys.insert("\(meetingKey)@dismissed")
        persisted.snoozedUntil = persisted.snoozedUntil.filter { !$0.key.hasPrefix("\(meetingKey)@") }
        saveState()
    }

    func snooze(_ m: Meeting, alertKey: String, minutes: Int) {
        stopAlert(alertKey)
        let now = Date()
        let requested = now.addingTimeInterval(Double(minutes * 60))
        persisted.snoozedUntil[alertKey] = m.start > now ? min(requested, m.start) : requested  // never snooze past a not-yet-started meeting's start
        saveState()
    }

    func snoozeUntilStart(_ m: Meeting, alertKey: String) {
        stopAlert(alertKey)
        guard m.start > Date() else { return }  // already started — "until start" would be the past; stopping is enough
        persisted.snoozedUntil[alertKey] = m.start
        saveState()
    }

    /// The popup/menu "Ignore" button: a recurring meeting ignores the WHOLE series (that's what
    /// "forever" means for a weekly standup — the old per-occurrence ignore let next week's alert
    /// fire again), a one-off ignores just that occurrence.
    func ignoreForever(_ m: Meeting) {
        if m.seriesId != nil { ignoreSeries(m) } else { ignoreOccurrence(m) }
    }

    /// Ignore just this one occurrence — also what the Settings picker's "This time" does.
    func ignoreOccurrence(_ m: Meeting) {
        stopAlerts(for: m.key)
        persisted.ignoredKeys.insert(m.key)
        persisted.ignoredTitles[m.key] = "\(m.title) — \(m.start.formatted(date: .abbreviated, time: .shortened))"
        saveState()
        tick()
    }

    /// Ignore every occurrence of a recurring meeting, past and future.
    func ignoreSeries(_ m: Meeting) {
        guard let seriesId = m.seriesId else { return ignoreOccurrence(m) }
        stopAlerts(for: m.key)
        persisted.ignoredSeriesIds.insert(seriesId)
        persisted.ignoredTitles[seriesId] = "\(m.title) — every occurrence"
        saveState()
        tick()
    }

    func unignore(_ id: String) {
        persisted.ignoredKeys.remove(id)
        persisted.ignoredSeriesIds.remove(id)
        persisted.ignoredTitles.removeValue(forKey: id)
        saveState()
        tick()
    }

    /// Everything currently ignored, labeled for the Settings list (raw id as fallback for
    /// entries that predate the label map).
    func ignoredEntries() -> [(id: String, label: String)] {
        persisted.ignoredSeriesIds.union(persisted.ignoredKeys)
            .map { ($0, persisted.ignoredTitles[$0] ?? $0) }
            .sorted { $0.1 < $1.1 }
    }

    /// Next 7 days of not-yet-ignored meetings, for the Settings pre-ignore picker.
    func upcomingWeek() -> [Meeting] {
        guard !testMode, !calendarAccessDenied else { return [] }
        let now = Date()
        return applyIgnores(fetchMeetings(from: now, to: now.addingTimeInterval(7 * 24 * 3600)))
            .sorted { $0.start < $1.start }
    }

    private func stopAlerts(for meetingKey: String) {
        // escalationTasks is keyed per-offset ("key@offset"), not per-meeting — cancel all of them.
        for alertKey in escalationTasks.keys.filter({ $0 == meetingKey || $0.hasPrefix("\(meetingKey)@") }) {
            stopAlert(alertKey)
        }
    }

    private func emit(_ line: String) {
        print(line)
        fflush(stdout)
    }

    private func loadConfigAndState() {
        try? FileManager.default.createDirectory(at: Self.configDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: Self.configURL.path) {
            saveConfig()
        }
        loadConfig()
        loadState()
    }

    private func loadConfig() {
        guard let data = try? Data(contentsOf: Self.configURL),
              let decoded = try? JSONDecoder().decode(Config.self, from: data),
              decoded != config else { return }  // skip the identical rewrite that'd fight a hand-edit
        config = decoded
    }

    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        persisted = decoded
    }

    private func saveState() {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        persisted.alertedKeys = Self.pruneOlderThan(persisted.alertedKeys, cutoff: cutoff)
        persisted.ignoredKeys = Self.pruneOlderThan(persisted.ignoredKeys, cutoff: cutoff)
        persisted.snoozedUntil = persisted.snoozedUntil.filter { $0.value >= cutoff }
        persisted.ignoredTitles = persisted.ignoredTitles.filter {  // labels live only as long as their entry
            persisted.ignoredKeys.contains($0.key) || persisted.ignoredSeriesIds.contains($0.key)
        }
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: Self.stateURL, options: .atomic)
    }

    /// Drops keys whose embedded epoch (the segment between the last "|" and an optional "@") is
    /// older than `cutoff`. Shared by alertedKeys (epoch@offset) and ignoredKeys (epoch, no
    /// suffix) — once an occurrence's specific epoch is a day old it'll never recur, so there's
    /// nothing left for either set to protect by keeping the key around forever.
    private static func pruneOlderThan(_ keys: Set<String>, cutoff: Date) -> Set<String> {
        keys.filter { key in
            guard let last = key.split(separator: "|").last,
                  let epoch = Double(last.split(separator: "@").first ?? last) else { return true }
            return epoch >= cutoff.timeIntervalSince1970
        }
    }
}
