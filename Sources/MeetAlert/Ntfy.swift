import Foundation

enum Ntfy {
    static func alert(_ m: Store.Meeting, token: String, cfg: Store.Config, test: Bool) async {
        let body = m.start < Date()
            ? "\(m.title) started \(Int(Date().timeIntervalSince(m.start) / 60))m ago."
            : "\(m.title) starts soon."
        await post(cfg: cfg, body: body, headers: [
            "X-Title": title(for: m, test: test),
            "X-Priority": "high",
            "X-Tags": "calendar",
            "X-Actions": "http, ACK, \(cfg.ntfyServer)/\(cfg.ntfyTopic), body=meetack \(token)"
        ])
    }

    static func urgent(_ m: Store.Meeting, cfg: Store.Config, test: Bool) async {
        await post(cfg: cfg, body: "\(m.title) — still unacknowledged.", headers: [
            "X-Title": title(for: m, test: test),
            "X-Priority": "urgent",
            "X-Tags": "rotating_light"
        ])
    }

    static func waitForAck(token: String, since: Int, deadline: Date, cfg: Store.Config) async -> Bool {
        guard !cfg.ntfyTopic.isEmpty,
              let url = URL(string: "\(cfg.ntfyServer)/\(cfg.ntfyTopic)/json?poll=1&since=\(since)") else { return false }
        while Date() < deadline {
            if Task.isCancelled { return false }
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
                for line in lines {
                    if let msg = try? JSONDecoder().decode(NtfyMessage.self, from: Data(line.utf8)),
                       msg.message == "meetack \(token)" {
                        return true
                    }
                }
            }
            try? await Task.sleep(for: .seconds(10))
        }
        return false
    }

    private struct NtfyMessage: Decodable { let message: String? }

    private static func title(for m: Store.Meeting, test: Bool) -> String {
        let prefix = (test && !m.title.hasPrefix("[TEST]")) ? "[TEST] " : ""
        return "\(prefix)\(m.title) @ \(m.start.formatted(date: .omitted, time: .shortened))"
    }

    private static func post(cfg: Store.Config, body: String, headers: [String: String]) async {
        guard !cfg.ntfyTopic.isEmpty,  // no topic configured → desktop-only mode
              let url = URL(string: "\(cfg.ntfyServer)/\(cfg.ntfyTopic)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        _ = try? await URLSession.shared.data(for: request)
    }
}
