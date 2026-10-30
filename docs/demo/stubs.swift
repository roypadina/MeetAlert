// Stand-ins for the two app types AlertPanel.swift refers to, so the REAL AlertContent/Theme compile unchanged.
// Store.Meeting mirrors the app's struct; Ntfy.provider(for:) is the app's function verbatim.
import AppKit

enum Store {
    struct Meeting: Identifiable {
        let key: String
        let title: String
        let start: Date
        let end: Date
        let hasPhysicalLocation: Bool
        let joinURL: URL?
        let seriesId: String?
        let calendarTitle: String
        let calendarColor: NSColor?
        var id: String { key }
    }
}

enum Ntfy {
    static func provider(for url: URL) -> String {
        let host = url.host()?.lowercased() ?? ""
        if host.contains("zoom") { return "Zoom" }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("teams") { return "Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("whereby") { return "Whereby" }
        return "Video call"
    }
}
