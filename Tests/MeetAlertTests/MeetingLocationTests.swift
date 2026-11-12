import Foundation
import XCTest
@testable import MeetAlert

@MainActor
final class MeetingLocationTests: XCTestCase {
    func testGoogleMeetLabelsAreNotPhysicalLocations() {
        for location in ["Google Meet", "Google Meet (instructions in description)"] {
            XCTAssertFalse(Store.hasPhysicalLocation(location), location)
        }
    }

    func testGoogleMeetLabelsIgnoreCaseAndWhitespace() {
        for location in [
            "  google meet (instructions in description)\n",
            "GOOGLE MEET (INSTRUCTIONS IN DESCRIPTION)",
            "Google\tMeet  (instructions in\ndescription)",
        ] {
            XCTAssertFalse(Store.hasPhysicalLocation(location), location)
        }
    }

    func testEmptyLocationsAndURLsRemainNonPhysical() {
        XCTAssertFalse(Store.hasPhysicalLocation(nil))
        for location in ["", " \n\t ", "https://meet.google.com/abc-defg-hij", "https://zoom.us/j/123"] {
            XCTAssertFalse(Store.hasPhysicalLocation(location), location)
        }
    }

    func testAddressesAndRoomNamesRemainPhysical() {
        for location in [
            "123 Main Street, Springfield",
            "Conference Room A",
            "Google Meeting Room, 123 Main Street",
            "123 Main Street — Google Meet (instructions in description)",
            "Google Meet (instructions in description)\nConference Room A",
        ] {
            XCTAssertTrue(Store.hasPhysicalLocation(location), location)
        }
    }

    func testGoogleMeetPlaceholderDoesNotAddTravelOffset() {
        let store = Store()  // No start(): no timers, EventKit access, or config writes.
        let meeting = meeting(location: "Google Meet (instructions in description)", online: true)
        XCTAssertEqual(store.offsets(for: meeting), store.config.alertMinutesBefore)
    }

    func testGoogleMeetPlaceholderWithoutJoinLinkStillDoesNotAddTravelOffset() {
        let store = Store()
        let meeting = meeting(location: "Google Meet (instructions in description)", online: false)
        XCTAssertEqual(store.offsets(for: meeting), store.config.alertMinutesBefore)
    }

    func testPhysicalLocationWithJoinLinkStillAddsTravelOffset() {
        let store = Store()
        let meeting = meeting(location: "123 Main Street, Springfield", online: true)
        XCTAssertEqual(store.offsets(for: meeting), store.config.alertMinutesBefore + [store.config.travelLeadMinutes])
    }

    private func meeting(location: String, online: Bool) -> Store.Meeting {
        let start = Date().addingTimeInterval(3600)
        return Store.Meeting(key: "synthetic", title: "Synthetic meeting", start: start,
                             end: start.addingTimeInterval(1800),
                             hasPhysicalLocation: Store.hasPhysicalLocation(location),
                             joinURL: online ? URL(string: "https://meet.google.com/abc-defg-hij") : nil,
                             seriesId: nil, calendarTitle: "Test", calendarColor: nil)
    }
}
