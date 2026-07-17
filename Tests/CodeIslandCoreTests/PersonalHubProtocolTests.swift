import XCTest
@testable import CodeIslandCore

final class PersonalHubProtocolTests: XCTestCase {
    func testCatalogContainsEveryPersonalBaselineModuleExactlyOnce() {
        XCTAssertEqual(PersonalHubCatalog.personalBaseline.count, 15)
        XCTAssertEqual(Set(PersonalHubCatalog.personalBaseline).count, 15)
        XCTAssertTrue(Set(PersonalHubCatalog.personalBaseline).isSubset(of: Set(PersonalHubModuleID.allCases)))
    }

    func testEveryBaselineModuleSupportsMacIPhoneAndWeb() {
        for id in PersonalHubCatalog.personalBaseline {
            let platforms = PersonalHubCatalog.definition(for: id).platforms
            XCTAssertTrue(platforms.contains(.mac), "\(id) is missing Mac support")
            XCTAssertTrue(platforms.contains(.iphone), "\(id) is missing iPhone support")
            XCTAssertTrue(platforms.contains(.web), "\(id) is missing web fallback support")
        }
    }

    func testAutoModePrioritizesWaitingAgent() {
        let context = PersonalHubAutoContext(
            foregroundBundleID: "com.apple.Safari",
            minutesUntilMeeting: 10,
            agentNeedsAttention: true
        )
        XCTAssertEqual(PersonalHubCatalog.resolvedMode(requested: .auto, context: context), .code)
    }

    func testAutoModeRecognizesCodeApplications() {
        let context = PersonalHubAutoContext(foregroundBundleID: "com.openai.codex")
        XCTAssertEqual(PersonalHubCatalog.resolvedMode(requested: .auto, context: context), .code)
    }

    func testAutoModeChoosesWorkForUpcomingMeeting() {
        let context = PersonalHubAutoContext(
            foregroundBundleID: "com.apple.finder",
            minutesUntilMeeting: 26
        )
        XCTAssertEqual(PersonalHubCatalog.resolvedMode(requested: .auto, context: context), .work)
    }

    func testAutoModeDefaultsToHome() {
        XCTAssertEqual(
            PersonalHubCatalog.resolvedMode(requested: .auto, context: PersonalHubAutoContext()),
            .home
        )
    }

    func testExplicitModeNeverAutoSwitches() {
        let context = PersonalHubAutoContext(agentNeedsAttention: true)
        XCTAssertEqual(PersonalHubCatalog.resolvedMode(requested: .home, context: context), .home)
        XCTAssertEqual(PersonalHubCatalog.resolvedMode(requested: .work, context: context), .work)
        XCTAssertEqual(PersonalHubCatalog.resolvedMode(requested: .code, context: context), .code)
    }

    func testSnapshotRoundTripPreservesActionBinding() throws {
        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = PersonalHubSnapshot(
            serverName: "Greg's Mac",
            generatedAt: Date(timeIntervalSince1970: 1_799_999_900),
            requestedMode: .auto,
            resolvedMode: .work,
            modules: [
                PersonalHubModuleSnapshot(
                    id: .calendar,
                    availability: .ready,
                    summary: "Standup in 26 min",
                    items: [
                        PersonalHubItem(
                            id: "event-1",
                            title: "Standup",
                            actions: [
                                PersonalHubAction(
                                    id: "join",
                                    label: "Join",
                                    role: .primary,
                                    targetID: "event-1",
                                    deepLink: URL(string: "https://meet.google.com/abc-defg-hij"),
                                    value: "review-seed",
                                    actionToken: "exact-token",
                                    actionExpiresAt: expiresAt
                                )
                            ]
                        )
                    ]
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(PersonalHubSnapshot.self, from: data), snapshot)
    }

    func testMediaItemRoundTripAndLegacyDecode() throws {
        let item = PersonalHubItem(
            id: "current",
            title: "Current song",
            artworkDataURL: "data:image/jpeg;base64,/9j/2Q==",
            mediaPosition: 42.5,
            mediaDuration: 180
        )
        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(PersonalHubItem.self, from: data), item)
        XCTAssertEqual(item.decodedArtworkJPEG, Data([0xFF, 0xD8, 0xFF, 0xD9]))

        let rejectedArtwork = PersonalHubItem(
            id: "unsafe",
            title: "Remote image",
            artworkDataURL: "data:image/png;base64,iVBORw0KGgo="
        )
        XCTAssertNil(rejectedArtwork.decodedArtworkJPEG)

        let legacy = try JSONDecoder().decode(
            PersonalHubItem.self,
            from: Data(#"{"id":"legacy","title":"Song","actions":[]}"#.utf8)
        )
        XCTAssertNil(legacy.artworkDataURL)
        XCTAssertNil(legacy.mediaPosition)
        XCTAssertNil(legacy.mediaDuration)
    }

    func testActionBindingChangesWithEveryMutableField() {
        let baseline = PersonalHubActionIntent(
            moduleID: .reminders,
            actionID: "add",
            targetID: "groceries",
            value: "Milk"
        )
        XCTAssertNotEqual(
            baseline.bindingID,
            PersonalHubActionIntent(
                moduleID: .notes,
                actionID: "add",
                targetID: "groceries",
                value: "Milk"
            ).bindingID
        )
        XCTAssertNotEqual(
            baseline.bindingID,
            PersonalHubActionIntent(
                moduleID: .reminders,
                actionID: "complete",
                targetID: "groceries",
                value: "Milk"
            ).bindingID
        )
        XCTAssertNotEqual(
            baseline.bindingID,
            PersonalHubActionIntent(
                moduleID: .reminders,
                actionID: "add",
                targetID: "work",
                value: "Milk"
            ).bindingID
        )
        XCTAssertNotEqual(
            baseline.bindingID,
            PersonalHubActionIntent(
                moduleID: .reminders,
                actionID: "add",
                targetID: "groceries",
                value: "Eggs"
            ).bindingID
        )
    }

    func testCalendarDraftRoundTripsThroughActionValue() throws {
        let draft = PersonalHubCalendarDraft(
            title: "Design review",
            start: Date(timeIntervalSince1970: 1_800_000_000),
            end: Date(timeIntervalSince1970: 1_800_003_600),
            joinURL: try XCTUnwrap(URL(string: "https://meet.google.com/abc-defg-hij")),
            notes: "Bring the latest mockups"
        )

        XCTAssertEqual(
            PersonalHubCalendarDraft.decodeActionValue(try XCTUnwrap(draft.encodedActionValue())),
            draft
        )
    }

    func testCalendarMonthBuildsSixLocalWeeksWithAdjacentDaysAndCounts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        calendar.firstWeekday = 1

        let reference = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 4, day: 15, hour: 12
        )))
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 4, day: 1, hour: 18
        )))
        let maySecond = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 5, day: 2, hour: 9
        )))

        let month = PersonalHubCalendarMonth.make(
            referenceDate: reference,
            selectedDate: selected,
            eventDates: [selected, selected.addingTimeInterval(3_600), maySecond],
            now: reference,
            calendar: calendar
        )

        XCTAssertEqual(month.days.count, 42)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: month.days[0].date),
                       DateComponents(year: 2026, month: 3, day: 29))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: month.days[41].date),
                       DateComponents(year: 2026, month: 5, day: 9))
        XCTAssertFalse(month.days[0].isInDisplayedMonth)
        XCTAssertTrue(month.days[3].isInDisplayedMonth)
        XCTAssertEqual(month.days.first(where: { calendar.isDate($0.date, inSameDayAs: selected) })?.eventCount, 2)
        XCTAssertEqual(month.days.first(where: { calendar.isDate($0.date, inSameDayAs: maySecond) })?.eventCount, 1)
        XCTAssertTrue(month.days.first(where: { calendar.isDate($0.date, inSameDayAs: reference) })?.isToday == true)
        XCTAssertTrue(calendar.isDate(month.selectedDate, inSameDayAs: selected))
    }

    func testCalendarMonthFallsBackToDisplayedMonthWhenSelectionIsOutsideGrid() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        calendar.firstWeekday = 1
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 15)))
        let outside = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))

        let month = PersonalHubCalendarMonth.make(
            referenceDate: reference,
            selectedDate: outside,
            eventDates: [],
            now: reference,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.day, from: month.selectedDate), 1)
        XCTAssertEqual(calendar.component(.month, from: month.selectedDate), 4)
        XCTAssertEqual(month.days.reduce(0) { $0 + $1.eventCount }, 0)
    }

    func testCalendarSnapshotRequestRoundTripsMonthSelectionAndDecodesLegacyPayload() throws {
        let request = PersonalHubSnapshotRequest(
            requestedMode: .work,
            calendarReferenceDate: Date(timeIntervalSince1970: 1_800_000_000),
            calendarSelectedDate: Date(timeIntervalSince1970: 1_800_086_400)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertEqual(try decoder.decode(PersonalHubSnapshotRequest.self, from: encoder.encode(request)), request)

        let legacy = try decoder.decode(
            PersonalHubSnapshotRequest.self,
            from: Data(#"{"requestedMode":"home"}"#.utf8)
        )
        XCTAssertEqual(legacy.requestedMode, .home)
        XCTAssertNil(legacy.calendarReferenceDate)
        XCTAssertNil(legacy.calendarSelectedDate)
    }

    func testReminderDraftSupportsStructuredAndLegacyValues() throws {
        let draft = PersonalHubReminderDraft(
            title: "Finish the deck",
            due: Date(timeIntervalSince1970: 1_800_000_000),
            calendarID: "work-list"
        )
        XCTAssertEqual(
            PersonalHubReminderDraft.decodeActionValue(try XCTUnwrap(draft.encodedActionValue())),
            draft
        )
        XCTAssertEqual(
            PersonalHubReminderDraft.decodeActionValue("Call the bank"),
            PersonalHubReminderDraft(title: "Call the bank")
        )
    }

    func testNewOptionalProtocolFieldsDecodeFromLegacyPayloads() throws {
        let decoder = JSONDecoder()
        let action = try decoder.decode(
            PersonalHubAction.self,
            from: Data(
                #"{"id":"join","label":"Join","role":"primary","targetID":"event-1"}"#.utf8
            )
        )
        let draft = try decoder.decode(
            PersonalHubReminderDraft.self,
            from: Data(#"{"title":"Call the bank","due":null}"#.utf8)
        )

        XCTAssertNil(action.value)
        XCTAssertNil(draft.calendarID)
    }

    func testConflictSafeNoteDraftRoundTripsAndSupportsLegacyText() throws {
        let draft = PersonalHubNoteDraft(
            text: "Launch checklist\n- [ ] Send invite",
            category: "Work",
            baseRevision: 7
        )

        XCTAssertEqual(
            PersonalHubNoteDraft.decodeActionValue(try XCTUnwrap(draft.encodedActionValue())),
            draft
        )
        XCTAssertEqual(
            PersonalHubNoteDraft.decodeActionValue("Legacy note text"),
            PersonalHubNoteDraft(text: "Legacy note text")
        )
    }

    func testChecklistMutationRoundTrips() throws {
        let mutation = PersonalHubChecklistMutation(lineIndex: 3, baseRevision: 9)
        XCTAssertEqual(
            PersonalHubChecklistMutation.decodeActionValue(try XCTUnwrap(mutation.encodedActionValue())),
            mutation
        )
    }

    func testModeRackConfigurationSanitizesDuplicatesUnknownModesAndNewModules() {
        let configuration = PersonalHubConfiguration.sanitized(
            .init(
                version: 1,
                racks: [
                    .init(mode: .work, modules: [.notes, .calendar, .notes]),
                    .init(mode: .auto, modules: [.system]),
                ],
                dashboardEnabled: true,
                knownModules: []
            )
        )

        XCTAssertEqual(configuration.rack(for: .work).prefix(2), [.notes, .calendar])
        XCTAssertEqual(Set(configuration.rack(for: .work)), Set(PersonalHubCatalog.modules(for: .work)))
        XCTAssertEqual(configuration.rack(for: .auto), configuration.rack(for: .home))
        XCTAssertTrue(configuration.dashboardEnabled)
    }

    func testModeRackMutationRoundTripsThroughActionValue() throws {
        let mutation = PersonalHubConfigurationMutation(
            mode: .code,
            modules: [.agents, .claude, .github],
            dashboardEnabled: false
        )

        XCTAssertEqual(
            PersonalHubConfigurationMutation.decodeActionValue(
                try XCTUnwrap(mutation.encodedActionValue())
            ),
            mutation
        )
    }

    func testDayProgressUsesTheProvidedLocalCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -8 * 60 * 60)!
        let now = Date(timeIntervalSince1970: 1_735_718_400) // 2025-01-01 08:00:00Z

        XCTAssertEqual(
            PersonalHubConfiguration.dayProgress(at: now, calendar: calendar),
            0,
            accuracy: 0.0001
        )
    }
}
