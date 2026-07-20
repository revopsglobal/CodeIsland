import XCTest
import CoreLocation
import EventKit
@testable import CodeIsland

@MainActor
final class GlancesModelTests: XCTestCase {
    func testCalendarCanUpgradeWriteOnlyAccess() {
        XCTAssertTrue(GlancesModel.canRequestFullCalendarAccess(.notDetermined))
        XCTAssertTrue(GlancesModel.canRequestFullCalendarAccess(.writeOnly))
        XCTAssertFalse(GlancesModel.canRequestFullCalendarAccess(.fullAccess))
        XCTAssertFalse(GlancesModel.canRequestFullCalendarAccess(.denied))
    }

    func testAuthorizationStatusNamesAreStableForHealthDiagnostics() {
        XCTAssertEqual(GlancesModel.eventKitAuthorizationStatusName(.notDetermined), "notDetermined")
        XCTAssertEqual(GlancesModel.eventKitAuthorizationStatusName(.restricted), "restricted")
        XCTAssertEqual(GlancesModel.eventKitAuthorizationStatusName(.denied), "denied")
        XCTAssertEqual(GlancesModel.eventKitAuthorizationStatusName(.fullAccess), "fullAccess")
        XCTAssertEqual(GlancesModel.eventKitAuthorizationStatusName(.writeOnly), "writeOnly")

        XCTAssertEqual(GlancesModel.locationAuthorizationStatusName(.notDetermined), "notDetermined")
        XCTAssertEqual(GlancesModel.locationAuthorizationStatusName(.restricted), "restricted")
        XCTAssertEqual(GlancesModel.locationAuthorizationStatusName(.denied), "denied")
        XCTAssertEqual(GlancesModel.locationAuthorizationStatusName(.authorizedAlways), "authorized")
        XCTAssertEqual(GlancesModel.locationAuthorizationStatusName(.authorized), "authorized")
    }

    func testReminderSelectionKeepsValidStoredLists() {
        let selected = GlancesModel.resolveReminderCalendarIDs(
            stored: ["work", "stale"],
            available: ["home", "work"],
            defaultID: "home"
        )

        XCTAssertEqual(selected, ["work"])
    }

    func testReminderSelectionFallsBackToDefaultInsteadOfAllLists() {
        let selected = GlancesModel.resolveReminderCalendarIDs(
            stored: [],
            available: ["home", "work", "shared"],
            defaultID: "home"
        )

        XCTAssertEqual(selected, ["home"])
    }

    func testReminderSelectionFallsBackToOneStableListWhenDefaultIsMissing() {
        let selected = GlancesModel.resolveReminderCalendarIDs(
            stored: ["stale"],
            available: ["work", "home"],
            defaultID: nil
        )

        XCTAssertEqual(selected, ["home"])
    }

    func testQuickTaskPrefersSelectedDefaultList() {
        let selected = GlancesModel.preferredReminderCalendarID(
            selectedIDs: ["work", "home"],
            orderedAvailableIDs: ["work", "home"],
            defaultID: "home"
        )

        XCTAssertEqual(selected, "home")
    }

    func testQuickTaskFallsBackToFirstSelectedListInDisplayOrder() {
        let selected = GlancesModel.preferredReminderCalendarID(
            selectedIDs: ["work"],
            orderedAvailableIDs: ["home", "work"],
            defaultID: "home"
        )

        XCTAssertEqual(selected, "work")
        XCTAssertEqual(GlancesModel.normalizedReminderTitle("  Finish the deck\n"), "Finish the deck")
    }

    func testReminderOrderingSupportsTopUpAndDown() {
        let ids = ["first", "second", "third"]

        XCTAssertEqual(
            GlancesModel.reorderedReminderIDs(ids, moving: "third", direction: "top"),
            ["third", "first", "second"]
        )
        XCTAssertEqual(
            GlancesModel.reorderedReminderIDs(ids, moving: "third", direction: "up"),
            ["first", "third", "second"]
        )
        XCTAssertEqual(
            GlancesModel.reorderedReminderIDs(ids, moving: "second", direction: "down"),
            ["first", "third", "second"]
        )
    }

    func testReminderOrderingClampsEdgesAndRejectsUnknownInputs() {
        let ids = ["first", "second"]

        XCTAssertEqual(
            GlancesModel.reorderedReminderIDs(ids, moving: "first", direction: "up"),
            ids
        )
        XCTAssertEqual(
            GlancesModel.reorderedReminderIDs(ids, moving: "second", direction: "down"),
            ids
        )
        XCTAssertNil(GlancesModel.reorderedReminderIDs(ids, moving: "missing", direction: "top"))
        XCTAssertNil(GlancesModel.reorderedReminderIDs(ids, moving: "first", direction: "sideways"))
    }

    func testTrustedMeetingProvidersAllowRealJoinLinks() throws {
        let links = [
            "https://us02web.zoom.us/j/123456789",
            "https://meet.google.com/abc-defg-hij",
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting",
            "https://acme.webex.com/meet/greg",
            "https://whereby.com/my-room",
        ]

        for link in links {
            XCTAssertTrue(GlancesModel.isTrustedJoinURL(try XCTUnwrap(URL(string: link))), link)
        }
    }

    func testTrustedMeetingProvidersRejectSpoofedAndInsecureLinks() throws {
        let links = [
            "https://attacker.example/?next=meet.google.com/abc-defg-hij",
            "https://meet.google.com.attacker.example/abc-defg-hij",
            "http://meet.google.com/abc-defg-hij",
            "https://example.com/meeting",
        ]

        for link in links {
            XCTAssertFalse(GlancesModel.isTrustedJoinURL(try XCTUnwrap(URL(string: link))), link)
        }
    }

    func testRecurringCalendarInstancesReceiveStableDistinctIDs() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let first = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 20, hour: 9
        )))
        let second = try XCTUnwrap(calendar.date(byAdding: .weekOfYear, value: 1, to: first))

        let firstID = GlancesModel.eventInstanceID(eventIdentifier: "recurring-series", start: first)
        let repeatedID = GlancesModel.eventInstanceID(eventIdentifier: "recurring-series", start: first)
        let secondID = GlancesModel.eventInstanceID(eventIdentifier: "recurring-series", start: second)

        XCTAssertEqual(firstID, repeatedID)
        XCTAssertNotEqual(firstID, secondID)
    }

    func testCalendarActionsResolveEventKitSourceIdentifier() {
        let event = GlancesModel.EventInfo(
            id: "event-123#456",
            sourceID: "event-123",
            title: "CodeIsland acceptance",
            start: Date(timeIntervalSince1970: 1_000),
            end: Date(timeIntervalSince1970: 2_000),
            joinURL: nil,
            notes: nil,
            isAllDay: false,
            calendarTitle: "Calendar",
            isEditable: true
        )

        XCTAssertEqual(GlancesModel.event(forSourceID: "event-123", in: [event]), event)
        XCTAssertNil(GlancesModel.event(forSourceID: event.id, in: [event]))
    }

    func testGeocodingURLExtractsZIPFromNaturalLocationInput() throws {
        let url = try XCTUnwrap(GlancesModel.geocodingURL(for: "San Francisco 94107"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.host, "geocoding-api.open-meteo.com")
        XCTAssertEqual(query["name"]!, "94107")
        XCTAssertEqual(query["count"]!, "1")
    }

    func testGeocodingURLKeepsCityNameWhenNoZIPIsPresent() throws {
        let url = try XCTUnwrap(GlancesModel.geocodingURL(for: "San Francisco"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(query["name"]!, "San Francisco")
    }

    func testGeocodingResponseParsesCoordinatesAndLabel() throws {
        let data = Data(
            """
            {"results":[{"name":"San Francisco","admin1":"California","latitude":37.7749,"longitude":-122.4194}]}
            """.utf8
        )

        let location = try XCTUnwrap(GlancesModel.parseGeocodedLocation(from: data))
        XCTAssertEqual(location.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(location.longitude, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(location.label, "San Francisco, California")
    }
}
