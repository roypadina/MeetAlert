import Foundation

enum Ntfy {
    static func alert(_ m: Store.Meeting, token: String, cfg: Store.Config, test: Bool, priority: String = "high") async -> Bool {
        let started = m.start < Date()
        let body = started
            ? "Started \(Int(Date().timeIntervalSince(m.start) / 60)) min ago (\(timeRange(m)))\n\(secondLine(m))"
            : "Starts in \(max(1, Int(ceil(m.start.timeIntervalSinceNow / 60)))) min (\(timeRange(m)))\n\(secondLine(m))"
        // ntfy caps actions at 3: ACK + (Join, when there's a joinURL) + Snooze 5m.
        var actions = [ackAction(token: token, cfg: cfg)]
        if let joinURL = m.joinURL { actions.append(joinAction(joinURL)) }
        actions.append(snoozeAction(token: token, cfg: cfg))
        // Emoji comes from the tag: away/urgent reads as a shout, a started meeting as a red dot.
        let tag = priority == "urgent" ? "loudspeaker" : started ? "red_circle" : "alarm_clock"
        return await jsonPost(cfg: cfg, title: title(for: m, test: test), message: body,
                               priority: priority == "urgent" ? 5 : 4, tags: [tag], actions: actions,
                               click: m.joinURL?.absoluteString)
    }

    /// Escalation re-push. Carries the same ACK (+ Join) action as the first push — the old plain-text
    /// version sent no actions at all, so once escalation kicked in there was no way to ack from the push.
    static func urgent(_ m: Store.Meeting, token: String, cfg: Store.Config, test: Bool,
                        attempt: Int = 1, of total: Int = 3) async -> Bool {
        var actions = [ackAction(token: token, cfg: cfg)]
        if let joinURL = m.joinURL { actions.append(joinAction(joinURL)) }
        let when = m.start <= Date()
            ? "started \(Int(Date().timeIntervalSince(m.start) / 60)) min ago"
            : "starts in \(max(1, Int(ceil(m.start.timeIntervalSinceNow / 60)))) min"
        let prefix = (test && !m.title.hasPrefix("[TEST]")) ? "[TEST] " : ""
        return await jsonPost(cfg: cfg, title: "\(prefix)Not acknowledged: \(m.title)",
                               message: "Alert \(attempt) of \(total) — \(when). Tap ACK or Snooze.",
                               priority: 5, tags: ["rotating_light"], actions: actions,
                               click: m.joinURL?.absoluteString)
    }

    static func agenda(body: String, cfg: Store.Config) async -> Bool {
        await jsonPost(cfg: cfg, title: "Today's agenda", message: body, priority: 3, tags: ["sunrise"])
    }

    static func test(cfg: Store.Config) async -> Bool {
        await jsonPost(cfg: cfg, title: "MeetAlert", message: "Phone push works.", priority: 3,
                       tags: ["white_check_mark"])
    }

    /// Meeting-provider name from the join link's host. Shared with the desktop panel's
    /// "Join <Provider>" button so the two surfaces always say the same word.
    static func provider(for url: URL) -> String {
        let host = url.host()?.lowercased() ?? ""
        if host.contains("zoom") { return "Zoom" }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("teams") { return "Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("whereby") { return "Whereby" }
        return "Video call"
    }

    private static func timeRange(_ m: Store.Meeting) -> String {
        "\(m.start.formatted(date: .omitted, time: .shortened))–\(m.end.formatted(date: .omitted, time: .shortened))"
    }

    private static func secondLine(_ m: Store.Meeting) -> String {
        if let url = m.joinURL { return "\(provider(for: url)) — tap Join" }
        return m.hasPhysicalLocation ? "In person — leave now" : "No meeting link"
    }

    enum AckOutcome { case acked, snoozed, timedOut }

    static func waitForAck(token: String, since: Int, deadline: Date, cfg: Store.Config) async -> AckOutcome {
        guard !cfg.ntfyTopic.isEmpty,
              let url = URL(string: "\(cfg.ntfyServer)/\(cfg.ntfyTopic)/json?poll=1&since=\(since)") else { return .timedOut }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        while Date() < deadline {
            if Task.isCancelled { return .timedOut }
            if let (data, _) = try? await URLSession.shared.data(for: request) {
                let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
                for line in lines {
                    guard let msg = try? JSONDecoder().decode(NtfyMessage.self, from: Data(line.utf8)) else { continue }
                    if msg.message == "meetack \(token)" { return .acked }
                    if msg.message == "meetsnooze \(token)" { return .snoozed }
                }
            }
            try? await Task.sleep(for: .seconds(10))
        }
        return .timedOut
    }

    private struct NtfyMessage: Decodable { let message: String? }

    // JSON publish API request/action shapes — see https://docs.ntfy.sh/publish/#publish-as-json
    private struct Action: Encodable {
        let action: String
        let label: String
        let url: String
        var method: String? = nil
        var body: String? = nil
        var headers: [String: String]? = nil
        var clear: Bool? = nil  // remove the notification when the button is tapped (also stops insistent ringing)
    }

    private struct Publish: Encodable {
        let topic: String
        var title: String?
        var message: String?
        var priority: Int?
        var tags: [String]?
        var actions: [Action]?
        var click: String?  // tapping the notification body opens the meeting link
    }

    // The ACK/Snooze taps themselves POST to the topic, which ntfy echoes back as a new
    // notification to every subscriber (including the phone that just tapped). These headers ride
    // along on THAT outgoing request to keep the echo silent instead of a second full-priority ping.
    private static let echoSilencingHeaders = ["X-Priority": "min", "X-Tags": "wastebasket"]

    private static func ackAction(token: String, cfg: Store.Config) -> Action {
        Action(action: "http", label: "ACK", url: "\(cfg.ntfyServer)/\(cfg.ntfyTopic)", method: "POST",
               body: "meetack \(token)", headers: echoSilencingHeaders, clear: true)
    }

    private static func snoozeAction(token: String, cfg: Store.Config) -> Action {
        Action(action: "http", label: "Snooze 5m", url: "\(cfg.ntfyServer)/\(cfg.ntfyTopic)", method: "POST",
               body: "meetsnooze \(token)", headers: echoSilencingHeaders, clear: true)
    }

    private static func joinAction(_ url: URL) -> Action {
        Action(action: "view", label: "Join \(provider(for: url))", url: url.absoluteString)
    }

    private static func title(for m: Store.Meeting, test: Bool) -> String {
        let prefix = (test && !m.title.hasPrefix("[TEST]")) ? "[TEST] " : ""
        return "\(prefix)\(m.title) · \(m.start.formatted(date: .omitted, time: .shortened))"
    }

    /// JSON publish to the server root (not the topic-suffixed URL) — full UTF-8 title/message
    /// (the old header-based API silently mangled emoji/non-Latin titles) and structured actions
    /// (no more hand-escaping commas/semicolons into a single header string). Returns whether the
    /// publish actually succeeded — an empty topic (push disabled by choice) is NOT a failure.
    private static func jsonPost(cfg: Store.Config, title: String, message: String, priority: Int,
                                  tags: [String] = [], actions: [Action] = [], click: String? = nil) async -> Bool {
        guard !cfg.ntfyTopic.isEmpty else { return true }
        guard let url = URL(string: cfg.ntfyServer) else { return false }
        let payload = Publish(topic: cfg.ntfyTopic, title: title, message: message, priority: priority,
                               tags: tags.isEmpty ? nil : tags, actions: actions.isEmpty ? nil : actions,
                               click: click)
        guard let body = try? JSONEncoder().encode(payload) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}
