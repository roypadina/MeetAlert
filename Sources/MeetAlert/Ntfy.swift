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
        return await jsonPost(cfg: cfg, flow: test ? "test-alert" : "meeting-alert", title: title(for: m, test: test), message: body,
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
        return await jsonPost(cfg: cfg, flow: "escalation", title: "\(prefix)Not acknowledged: \(m.title)",
                               message: "Alert \(attempt) of \(total) — \(when). Tap ACK or Snooze.",
                               priority: 5, tags: ["rotating_light"], actions: actions,
                               click: m.joinURL?.absoluteString)
    }

    static func agenda(body: String, cfg: Store.Config) async -> Bool {
        await jsonPost(cfg: cfg, flow: "agenda", title: "Today's agenda", message: body, priority: 3, tags: ["sunrise"])
    }

    static func test(cfg: Store.Config) async -> Bool {
        await jsonPost(cfg: cfg, flow: "test", title: "MeetAlert", message: "Phone push works.", priority: 3,
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
        for (k, v) in authHeaders(for: url, cfg: cfg) { request.setValue(v, forHTTPHeaderField: k) }
        while Date() < deadline {
            if Task.isCancelled { return .timedOut }
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let outcome = ackOutcome(in: data, token: token) { return outcome }
            try? await Task.sleep(for: .seconds(10))
        }
        return .timedOut
    }

    /// Exact-match on the reply body, so the footer on our own outbound alerts can never look like an ACK.
    static func ackOutcome(in data: Data, token: String) -> AckOutcome? {
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let msg = try? JSONDecoder().decode(NtfyMessage.self, from: Data(line.utf8)) else { continue }
            if msg.message == "meetack \(token)" { return .acked }
            if msg.message == "meetsnooze \(token)" { return .snoozed }
        }
        return nil
    }

    struct NtfyMessage: Decodable { let message: String?; var id: String? = nil }

    // JSON publish API request/action shapes — see https://docs.ntfy.sh/publish/#publish-as-json
    struct Action: Encodable {
        let action: String
        let label: String
        let url: String
        var method: String? = nil
        var body: String? = nil
        var headers: [String: String]? = nil
        var clear: Bool? = nil  // remove the notification when the button is tapped (also stops insistent ringing)
    }

    struct Publish: Encodable {
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

    static func ackAction(token: String, cfg: Store.Config) -> Action {
        postAction("ACK", body: "meetack \(token)", cfg: cfg)
    }

    static func snoozeAction(token: String, cfg: Store.Config) -> Action {
        postAction("Snooze 5m", body: "meetsnooze \(token)", cfg: cfg)
    }

    // The phone runs these, so the bearer token has to ride in the action itself.
    private static func postAction(_ label: String, body: String, cfg: Store.Config) -> Action {
        let url = "\(cfg.ntfyServer)/\(cfg.ntfyTopic)"
        let headers = echoSilencingHeaders.merging(URL(string: url).map { authHeaders(for: $0, cfg: cfg) } ?? [:]) { a, _ in a }
        return Action(action: "http", label: label, url: url, method: "POST", body: body, headers: headers, clear: true)
    }

    /// `Authorization: Bearer` only for a non-empty token and a URL on the same origin as `ntfyServer`.
    static func authHeaders(for url: URL, cfg: Store.Config) -> [String: String] {
        guard !cfg.ntfyToken.isEmpty, let server = URL(string: cfg.ntfyServer), sameOrigin(url, server) else { return [:] }
        return ["Authorization": "Bearer \(cfg.ntfyToken)"]
    }

    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        func origin(_ u: URL) -> [String?] {
            let scheme = u.scheme?.lowercased()
            return [scheme, u.host()?.lowercased(), String(u.port ?? (scheme == "http" ? 80 : 443))]
        }
        return a.host() != nil && origin(a) == origin(b)
    }

    /// Trace footer from the vault's ntfy rules: sender / flow / event / log.
    static func footer(flow: String, event: String, host: String = shortHost) -> String {
        "\n\nsender: meetalert@\(host)\nflow: \(flow)\nevent: \(event)\nlog: ~/Library/Logs/MeetAlert.log"
    }

    static var shortHost: String {
        String(ProcessInfo.processInfo.hostName.split(separator: ".").first ?? "mac")
    }

    /// `YYYYMMDD-HHMMSS-<4 hex>`, local time.
    static func eventID(_ now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "\(f.string(from: now))-\(String(format: "%04x", UInt16.random(in: 0...UInt16.max)))"
    }

    /// The titled outbound message. `meetalert` is always the first tag.
    static func payload(cfg: Store.Config, topic: String, flow: String, event: String, title: String, message: String,
                        priority: Int, tags: [String], actions: [Action], click: String?) -> Publish {
        Publish(topic: topic, title: title, message: message + footer(flow: flow, event: event), priority: priority,
                tags: ["meetalert"] + tags, actions: actions.isEmpty ? nil : actions, click: click)
    }

    /// Timeout (no status) or any non-2xx on the primary → try the fallback, if one is configured.
    static func shouldFallback(status: Int?, cfg: Store.Config) -> Bool {
        guard !cfg.ntfyFallbackURL.isEmpty else { return false }
        return !(status.map { (200...299).contains($0) } ?? false)
    }

    /// Splits a full topic URL (https://host/topic) into the server root and the topic.
    static func fallbackTarget(_ s: String) -> (root: URL, topic: String)? {
        guard let u = URL(string: s), let scheme = u.scheme, let host = u.host(), u.lastPathComponent.count > 0,
              u.lastPathComponent != "/",
              let root = URL(string: "\(scheme)://\(host)\(u.port.map { ":\($0)" } ?? "")") else { return nil }
        return (root, u.lastPathComponent)
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
    /// A failed primary falls back to `ntfyFallbackURL` (no auth, no actions); success there counts as sent.
    private static func jsonPost(cfg: Store.Config, flow: String, title: String, message: String, priority: Int,
                                  tags: [String] = [], actions: [Action] = [], click: String? = nil) async -> Bool {
        guard !cfg.ntfyTopic.isEmpty else { return true }
        guard let url = URL(string: cfg.ntfyServer) else { return false }
        let event = eventID()
        let primary = payload(cfg: cfg, topic: cfg.ntfyTopic, flow: flow, event: event, title: title, message: message,
                              priority: priority, tags: tags, actions: actions, click: click)
        let r = await post(primary, to: url, headers: authHeaders(for: url, cfg: cfg))
        log(event: event, topic: cfg.ntfyTopic, result: r)
        if let status = r.status, (200...299).contains(status) { return true }
        guard shouldFallback(status: r.status, cfg: cfg), let fb = fallbackTarget(cfg.ntfyFallbackURL) else { return false }
        let backup = payload(cfg: cfg, topic: fb.topic, flow: flow, event: event, title: title, message: message,
                             priority: priority, tags: tags, actions: [], click: click)
        let fr = await post(backup, to: fb.root, headers: [:])
        log(event: event, topic: "fallback", result: fr)  // the public topic name is a secret: never logged
        return fr.status.map { (200...299).contains($0) } ?? false
    }

    private static func post(_ payload: Publish, to url: URL, headers: [String: String]) async -> (status: Int?, id: String) {
        guard let body = try? JSONEncoder().encode(payload) else { return (nil, "-") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return (nil, "-") }
        let id = (try? JSONDecoder().decode(NtfyMessage.self, from: data))?.id ?? "-"
        return (http.statusCode, id)
    }

    /// One line per send, same event id as the message footer. Never the token.
    private static func log(event: String, topic: String, result: (status: Int?, id: String)) {
        let line = "\(Date().formatted(.iso8601)) ntfy event=\(event) topic=\(topic) http=\(result.status.map(String.init) ?? "timeout") id=\(result.id)\n"
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MeetAlert.log")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
