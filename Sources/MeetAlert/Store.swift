import EventKit
import Foundation
import Observation
import ServiceManagement

@Observable @MainActor
final class Store {
    struct Meeting: Identifiable {
        let key: String
        let title: String
        let start: Date
        var id: String { key }
    }

    struct Config: Codable {
        var leadMinutes = 3
        var lateAlertMinutes = 10  // still alert this long after start (covers Google→macOS sync lag)
        var escalationSeconds = 120
        var ignoreAllDay = true
        var ignoreKeywords: [String] = []
        var ntfyServer = "https://ntfy.sh"
        var ntfyTopic = ""  // empty = phone notifications disabled; set your private topic
        var calendarIds: [String]? = nil  // nil = all calendars
    }

    struct Persisted: Codable {
        var ignoredKeys: Set<String> = []
        var alertedKeys: Set<String> = []  // "identifier|epoch" — epoch used to prune >24h old
    }

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/meetalert")
    static let configURL = configDir.appendingPathComponent("config.json")
    static let stateURL = configDir.appendingPathComponent("state.json")

    var menuBarText = ""
    var upcomingList: [Meeting] = []
    var snoozedUntil: [String: Date] = [:]
    var calendarAccessDenied = false

    private let testMode = ProcessInfo.processInfo.environment["MEETALERT_TEST"] == "1"
    @ObservationIgnored private lazy var ekStore = EKEventStore()  // never touched in test mode
    var config = Config() { didSet { saveConfig() } }  // Settings GUI + config.json both write here
    private var persisted = Persisted()
    private var testMeetings: [Meeting] = []
    private var escalationTasks: [String: Task<Void, Never>] = [:]
    private var timer: Timer?

    func start() {
        loadConfigAndState()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if testMode {
            scheduleTestMeeting()
            return
        }
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()  // launch at login
        }
        Task { await requestAccessAndTick() }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func requestAccessAndTick() async {
        do {
            calendarAccessDenied = !(try await ekStore.requestFullAccessToEvents())
        } catch {
            calendarAccessDenied = true
        }
        tick()
    }

    private func scheduleTestMeeting() {
        Task {
            try? await Task.sleep(for: .seconds(10))
            let start = Date().addingTimeInterval(180)
            testMeetings = [Meeting(key: "test|\(Int(start.timeIntervalSince1970))",
                                     title: "[TEST] MeetAlert pipeline",
                                     start: start)]
            tick()
        }
    }

    /// The only scheduler: scan, update menu text, fire due meetings, re-show due snoozes.
    func tick() {
        loadConfig()
        let now = Date()
        let list = upcoming()
        upcomingList = Array(list.prefix(4))
        menuBarText = calendarAccessDenied ? "⚠︎ no calendar access" : menuBarTextFor(list, now: now)

        for m in list {
            if let due = snoozedUntil[m.key], now >= due {
                snoozedUntil.removeValue(forKey: m.key)
                showPanel(m, token: nil)  // re-show only, no re-arm
                continue
            }
            let dueSoon = m.start.timeIntervalSince(now) <= Double(config.leadMinutes * 60)
            let notStale = now.timeIntervalSince(m.start) <= Double(config.lateAlertMinutes * 60)
            if dueSoon && notStale && !persisted.alertedKeys.contains(m.key) {
                fire(m)
            }
        }
    }

    private func upcoming() -> [Meeting] {
        let source: [Meeting]
        if testMode {
            source = testMeetings
        } else if calendarAccessDenied {
            source = []
        } else {
            let now = Date()
            let calendars = config.calendarIds.map { ids in
                ekStore.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
            }
            let predicate = ekStore.predicateForEvents(withStart: now.addingTimeInterval(-Double(config.lateAlertMinutes * 60)),
                                                         end: now.addingTimeInterval(12 * 3600),
                                                         calendars: calendars)
            source = ekStore.events(matching: predicate)
                .filter { $0.status != .canceled }
                .filter { !(config.ignoreAllDay && $0.isAllDay) }
                .filter { event in
                    !config.ignoreKeywords.contains { (event.title ?? "").localizedCaseInsensitiveContains($0) }
                }
                .map { event in
                    let epoch = Int(event.startDate.timeIntervalSince1970)
                    return Meeting(key: "\(event.eventIdentifier ?? event.title ?? "untitled")|\(epoch)",
                                   title: event.title ?? "(untitled)",
                                   start: event.startDate)
                }
        }
        return source
            .filter { !persisted.ignoredKeys.contains($0.key) }
            .sorted { $0.start < $1.start }
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
        guard let next = list.first, next.start.timeIntervalSince(now) <= 2 * 3600 else { return "" }
        let secondsLeft = Int(next.start.timeIntervalSince(now))
        if secondsLeft <= 0 { return "now \(next.title)" }
        return "\(Int(ceil(Double(secondsLeft) / 60)))m \(next.title)"
    }

    private func fire(_ m: Meeting) {
        persisted.alertedKeys.insert(m.key)
        saveState()
        let token = String(Int(m.start.timeIntervalSince1970))
        if testMode { emit("fired \(token)") }
        showPanel(m, token: token)

        let since = Int(Date().timeIntervalSince1970)
        let deadline = Date().addingTimeInterval(Double(testMode ? 20 : config.escalationSeconds))
        let cfg = config
        let testMode = testMode
        escalationTasks[m.key] = Task {
            let acked = await Ntfy.waitForAck(token: token, since: since, deadline: deadline, cfg: cfg)
            guard !Task.isCancelled else { return }
            if acked {
                await MainActor.run { self.ack(m.key) }
            } else {
                await Ntfy.urgent(m, cfg: cfg, test: testMode)
                if testMode { await MainActor.run { self.emit("escalated \(token)") } }
            }
        }
        Task { await Ntfy.alert(m, token: token, cfg: cfg, test: testMode) }
    }

    /// token == nil means "re-show a snoozed panel" (no ntfy, no escalation).
    private func showPanel(_ m: Meeting, token: String?) {
        AlertPanel.show(m,
            onAck: { [weak self] in self?.ack(m.key) },
            onSnooze: { [weak self] minutes in self?.snooze(m, minutes: minutes) },
            onSnoozeStart: { [weak self] in self?.snoozeUntilStart(m) },
            onIgnore: { [weak self] in self?.ignoreForever(m.key) })
    }

    func ack(_ key: String) {
        escalationTasks[key]?.cancel()
        escalationTasks.removeValue(forKey: key)
        if testMode, let token = key.split(separator: "|").last {
            emit("acked \(token)")
        }
    }

    func snooze(_ m: Meeting, minutes: Int) {
        ack(m.key)  // snooze counts as ack
        snoozedUntil[m.key] = Date().addingTimeInterval(Double(minutes * 60))
    }

    func snoozeUntilStart(_ m: Meeting) {
        ack(m.key)
        snoozedUntil[m.key] = m.start
    }

    func ignoreForever(_ key: String) {
        ack(key)
        persisted.ignoredKeys.insert(key)
        saveState()
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
              let decoded = try? JSONDecoder().decode(Config.self, from: data) else { return }
        config = decoded
    }

    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: Self.configURL)
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        persisted = decoded
    }

    private func saveState() {
        let cutoff = Date().addingTimeInterval(-24 * 3600).timeIntervalSince1970
        persisted.alertedKeys = persisted.alertedKeys.filter { key in
            guard let epoch = key.split(separator: "|").last.flatMap({ Double($0) }) else { return true }
            return epoch >= cutoff
        }
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: Self.stateURL)
    }
}
