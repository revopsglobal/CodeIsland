import XCTest
@testable import CodeIsland

@MainActor
final class GlancesModelTests: XCTestCase {
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
