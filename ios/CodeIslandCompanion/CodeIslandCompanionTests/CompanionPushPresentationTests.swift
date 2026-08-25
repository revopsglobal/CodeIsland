import XCTest
@testable import CodeIslandCompanion
import UserNotifications

final class CompanionPushPresentationTests: XCTestCase {
    func testLiveActivityPairingScopeRequiresExactIdentityOnceKnown() {
        XCTAssertTrue(LiveActivityPairingScope.accepts(
            activityPairingDeviceID: nil,
            identity: .unpaired
        ))
        XCTAssertTrue(LiveActivityPairingScope.accepts(
            activityPairingDeviceID: "device-a",
            identity: .paired("device-a")
        ))
        XCTAssertFalse(LiveActivityPairingScope.accepts(
            activityPairingDeviceID: nil,
            identity: .paired("device-a")
        ))
        XCTAssertFalse(LiveActivityPairingScope.accepts(
            activityPairingDeviceID: "device-b",
            identity: .paired("device-a")
        ))
        XCTAssertFalse(LiveActivityPairingScope.accepts(
            activityPairingDeviceID: "device-a",
            identity: .unpaired
        ))
        XCTAssertFalse(LiveActivityPairingScope.accepts(
            activityPairingDeviceID: nil,
            identity: .credentialPresentButIdentityMissing
        ))
        XCTAssertFalse(LiveActivityPairingScope.accepts(
            activityPairingDeviceID: "device-a",
            identity: .credentialPresentButIdentityMissing
        ))
        XCTAssertFalse(LiveActivityPairingIdentity.credentialPresentButIdentityMissing.canCreateOwnedActivity)
        XCTAssertFalse(
            LiveActivityPairingIdentity.credentialPresentButIdentityMissing.canRegisterHostScopedArtifacts
        )
        XCTAssertFalse(LiveActivityPairingScope.accepts(
            activityPairingDeviceID: nil,
            identity: .paired("  ")
        ))
        XCTAssertFalse(LiveActivityPairingIdentity.paired("  ").canCreateOwnedActivity)
        XCTAssertFalse(LiveActivityPairingIdentity.paired("").canRegisterHostScopedArtifacts)
    }

    func testNearbyTransportCanDriveLiveActivityOnlyWhileUnpaired() throws {
        let accepted = try XCTUnwrap(LocalTransportLiveActivityScope.capture(
            generation: 4,
            identity: .unpaired
        ))
        XCTAssertNil(LocalTransportLiveActivityScope.capture(
            generation: 4,
            identity: .credentialPresentButIdentityMissing
        ))
        XCTAssertNil(LocalTransportLiveActivityScope.capture(
            generation: 4,
            identity: .paired("device-b")
        ))

        // Mac A may have enqueued local work just before the A→B transition.
        // The captured unpaired generation cannot resume into B's activity.
        XCTAssertFalse(accepted.isCurrent(
            generation: 5,
            identity: .paired("device-b")
        ))
    }

    func testQueuedOldPairingAttentionCannotRouteAfterIdentitySwitch() {
        let taskID = UUID()
        XCTAssertNil(ScopedRemoteAttentionRoute.resolve(
            requestID: taskID.uuidString.lowercased(),
            kind: .task,
            state: .pending,
            eventPairingDeviceID: "device-a",
            currentIdentity: .paired("device-b")
        ))
        XCTAssertNil(ScopedRemoteAttentionRoute.resolve(
            requestID: "approval-a",
            kind: .approval,
            state: .pending,
            eventPairingDeviceID: nil,
            currentIdentity: .paired("device-b")
        ))
        XCTAssertEqual(
            ScopedRemoteAttentionRoute.resolve(
                requestID: taskID.uuidString.lowercased(),
                kind: .task,
                state: .pending,
                eventPairingDeviceID: "device-b",
                currentIdentity: .paired("device-b")
            ),
            .task(taskID)
        )
    }

    func testLiveActivityTapRequiresExactPairingOwner() throws {
        let taskID = UUID()
        let urlA = try XCTUnwrap(CodeIslandActivityAttentionLink.url(
            host: "tasks",
            path: taskID.uuidString.lowercased(),
            pairingDeviceID: "device-a"
        ))
        let urlB = try XCTUnwrap(CodeIslandActivityAttentionLink.url(
            host: "tasks",
            path: taskID.uuidString.lowercased(),
            pairingDeviceID: "device-b"
        ))
        let localURL = try XCTUnwrap(CodeIslandActivityAttentionLink.url(
            host: "tasks",
            path: taskID.uuidString.lowercased(),
            pairingDeviceID: nil
        ))
        XCTAssertEqual(CodeIslandActivityAttentionLink.pairingDeviceID(from: urlA), "device-a")
        XCTAssertEqual(CodeIslandActivityAttentionLink.pairingDeviceID(from: urlB), "device-b")
        XCTAssertNil(CodeIslandActivityAttentionLink.pairingDeviceID(from: localURL))

        let routeA = try XCTUnwrap(PersonalHubDeepLink(url: urlA))
        XCTAssertFalse(RemoteDeepLinkPairingScope.accepts(
            url: urlA,
            route: routeA,
            currentIdentity: .paired("device-b")
        ))
        XCTAssertTrue(RemoteDeepLinkPairingScope.accepts(
            url: urlB,
            route: try XCTUnwrap(PersonalHubDeepLink(url: urlB)),
            currentIdentity: .paired("device-b")
        ))
        let localRoute = try XCTUnwrap(PersonalHubDeepLink(url: localURL))
        XCTAssertTrue(RemoteDeepLinkPairingScope.accepts(
            url: localURL,
            route: localRoute,
            currentIdentity: .unpaired
        ))
        XCTAssertFalse(RemoteDeepLinkPairingScope.accepts(
            url: localURL,
            route: localRoute,
            currentIdentity: .credentialPresentButIdentityMissing
        ))
        XCTAssertFalse(RemoteDeepLinkPairingScope.accepts(
            url: localURL,
            route: localRoute,
            currentIdentity: .paired("device-b")
        ))
        let genericApproval = PersonalHubDeepLink.pendingApproval(id: nil)
        XCTAssertTrue(RemoteDeepLinkPairingScope.accepts(
            url: genericApproval.url,
            route: genericApproval,
            currentIdentity: .paired("device-b")
        ))
    }

    func testLegacyPairResponseStaysUnresolvedUntilAuthenticatedBackfill() throws {
        let data = Data(#"{"deviceToken":"legacy-token","serverName":"Old Mac"}"#.utf8)
        let response = try JSONDecoder().decode(RemotePairResponse.self, from: data)
        let unresolved = LiveActivityPairingIdentity.resolve(
            credential: response.deviceToken,
            pairingDeviceID: response.deviceId
        )
        XCTAssertEqual(unresolved, .credentialPresentButIdentityMissing)
        XCTAssertFalse(unresolved.canRegisterHostScopedArtifacts)
        XCTAssertEqual(
            LiveActivityPairingIdentity.resolve(
                credential: response.deviceToken,
                pairingDeviceID: "authenticated-device"
            ),
            .paired("authenticated-device")
        )
    }

    func testPairingIdentityStorePersistsAndClearsDeviceID() {
        let suiteName = "CompanionPushPresentationTests.Pairing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RemotePairingIdentityStore.store(
            " device-a ",
            forCredential: "credential-a",
            defaults: defaults
        )
        XCTAssertEqual(
            RemotePairingIdentityStore.current(forCredential: "credential-a", defaults: defaults),
            "device-a"
        )
        XCTAssertNil(
            RemotePairingIdentityStore.current(forCredential: "credential-b", defaults: defaults)
        )

        RemotePairingIdentityStore.store(nil, forCredential: nil, defaults: defaults)
        XCTAssertNil(
            RemotePairingIdentityStore.current(forCredential: "credential-a", defaults: defaults)
        )
    }

    func testRuntimePairingIdentityFailsClosedBeforeCurrentProcessPublishesIt() {
        let suiteName = "CompanionPushPresentationTests.RuntimePairing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("paired", forKey: "codeisland.remote.runtimePairingIdentity.v1")
        defaults.set("old-device", forKey: "codeisland.remote.runtimePairingDeviceID.v1")

        XCTAssertEqual(
            RemotePairingIdentityStore.runtimeIdentity(defaults: defaults),
            .credentialPresentButIdentityMissing
        )

        RemotePairingIdentityStore.publishRuntimeIdentity(.paired("current-device"), defaults: defaults)
        XCTAssertEqual(
            RemotePairingIdentityStore.runtimeIdentity(defaults: defaults),
            .paired("current-device")
        )

        let validRecord = try! XCTUnwrap(defaults.data(
            forKey: RemotePairingIdentityStore.runtimeIdentityRecordKey
        ))
        var malformed = try! XCTUnwrap(
            JSONSerialization.jsonObject(with: validRecord) as? [String: Any]
        )
        malformed["pairingDeviceID"] = "   "
        defaults.set(
            try! JSONSerialization.data(withJSONObject: malformed),
            forKey: RemotePairingIdentityStore.runtimeIdentityRecordKey
        )
        XCTAssertEqual(
            RemotePairingIdentityStore.runtimeIdentity(defaults: defaults),
            .credentialPresentButIdentityMissing
        )
    }

    func testLegacyLiveActivityAttributesDecodeWithoutPairingDeviceID() throws {
        let data = Data(#"{"sessionId":"legacy-request"}"#.utf8)

        let attributes = try JSONDecoder().decode(CodeIslandActivityAttributes.self, from: data)

        XCTAssertEqual(attributes.sessionId, "legacy-request")
        XCTAssertNil(attributes.pairingDeviceID)
    }

    @MainActor
    func testPushReceiptIsQuarantinedUntilPairingIdentityIsResolved() {
        UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.receiptsKey)
        defer {
            UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.receiptsKey)
            RemotePairingIdentityStore.publishRuntimeIdentity(.unpaired)
        }
        let delegate = CompanionAppDelegate()
        let issuedAt = Date().addingTimeInterval(-2)

        RemotePairingIdentityStore.publishRuntimeIdentity(.credentialPresentButIdentityMissing)
        let unresolved = RemoteAttentionPushEnvelope(
            eventID: "pending-identity-event",
            kind: .approval,
            state: .pending,
            requestID: "pending-identity-request",
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(600)
        )
        XCTAssertEqual(delegate.processLegacy(unresolved.payloadFields), .accepted)
        XCTAssertTrue(LiveActivityTokenMailbox.pendingReceipts().isEmpty)

        RemotePairingIdentityStore.publishRuntimeIdentity(.paired("device-a"))
        let paired = RemoteAttentionPushEnvelope(
            eventID: "paired-identity-event",
            kind: .approval,
            state: .pending,
            requestID: "paired-identity-request",
            pairingDeviceID: "device-a",
            issuedAt: issuedAt.addingTimeInterval(1),
            expiresAt: issuedAt.addingTimeInterval(601)
        )
        XCTAssertEqual(delegate.processLegacy(paired.payloadFields), .accepted)
        XCTAssertEqual(LiveActivityTokenMailbox.pendingReceipts().count, 1)
    }

    @MainActor
    func testMismatchedAndLegacyPushesCannotWriteCurrentPairingRoutesOrReceipts() {
        let pendingKey = "codeisland.remote.pendingApprovalID"
        let historyKey = "codeisland.remote.pushHistory.v1"
        UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.receiptsKey)
        UserDefaults.standard.removeObject(forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: historyKey)
        defer {
            UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.receiptsKey)
            UserDefaults.standard.removeObject(forKey: pendingKey)
            UserDefaults.standard.removeObject(forKey: historyKey)
            RemotePairingIdentityStore.publishRuntimeIdentity(.unpaired)
        }
        RemotePairingIdentityStore.publishRuntimeIdentity(.paired("device-b"))
        let delegate = CompanionAppDelegate()
        let issuedAt = Date().addingTimeInterval(-2)

        let mismatched = RemoteAttentionPushEnvelope(
            eventID: "old-mac-event",
            kind: .approval,
            state: .pending,
            requestID: "old-mac-request",
            pairingDeviceID: "device-a",
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(600)
        )
        XCTAssertEqual(delegate.processLegacy(mismatched.payloadFields), .rejectedStale)
        XCTAssertTrue(LiveActivityTokenMailbox.pendingReceipts().isEmpty)
        XCTAssertNil(UserDefaults.standard.string(forKey: pendingKey))
        XCTAssertNil(UserDefaults.standard.dictionary(forKey: historyKey))

        let legacy = RemoteAttentionPushEnvelope(
            eventID: "legacy-mac-event",
            kind: .approval,
            state: .pending,
            requestID: "legacy-mac-request",
            issuedAt: issuedAt.addingTimeInterval(1),
            expiresAt: issuedAt.addingTimeInterval(601)
        )
        XCTAssertEqual(delegate.processLegacy(legacy.payloadFields), .accepted)
        XCTAssertTrue(LiveActivityTokenMailbox.pendingReceipts().isEmpty)
        XCTAssertNil(UserDefaults.standard.string(forKey: pendingKey))
    }

    @MainActor
    func testTaskHistoryFromOldPairingCannotRejectNewPairingState() {
        let historyKey = "codeisland.remote.pushHistory.v1"
        let taskHistoryKey = "codeisland.remote.taskPushState.v1"
        UserDefaults.standard.removeObject(forKey: historyKey)
        UserDefaults.standard.removeObject(forKey: taskHistoryKey)
        UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.receiptsKey)
        defer {
            UserDefaults.standard.removeObject(forKey: historyKey)
            UserDefaults.standard.removeObject(forKey: taskHistoryKey)
            UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.receiptsKey)
            RemotePairingIdentityStore.publishRuntimeIdentity(.unpaired)
        }
        let delegate = CompanionAppDelegate()
        let taskID = UUID().uuidString.lowercased()
        let now = Date()

        RemotePairingIdentityStore.publishRuntimeIdentity(.paired("device-a"))
        let terminalA = RemoteAttentionPushEnvelope(
            eventID: "terminal-a",
            kind: .task,
            state: .resolved,
            requestID: taskID,
            taskState: .verified,
            pairingDeviceID: "device-a",
            issuedAt: now.addingTimeInterval(-2),
            expiresAt: now.addingTimeInterval(600)
        )
        XCTAssertEqual(delegate.processLegacy(terminalA.payloadFields), .accepted)

        RemotePairingIdentityStore.publishRuntimeIdentity(.paired("device-b"))
        let needsYouB = RemoteAttentionPushEnvelope(
            eventID: "pending-b",
            kind: .task,
            state: .pending,
            requestID: taskID,
            taskState: .needsYou,
            pairingDeviceID: "device-b",
            issuedAt: now.addingTimeInterval(-1),
            expiresAt: now.addingTimeInterval(601)
        )
        XCTAssertEqual(delegate.processLegacy(needsYouB.payloadFields), .accepted)
        let taskHistory = UserDefaults.standard.dictionary(forKey: taskHistoryKey) as? [String: String]
        XCTAssertEqual(taskHistory?["device-a:\(taskID)"], RemoteTaskState.verified.rawValue)
        XCTAssertEqual(taskHistory?["device-b:\(taskID)"], RemoteTaskState.needsYou.rawValue)
    }

    func testNotificationTransactionCannotWriteOldPairingArtifactsAfterReplacement() {
        let pendingKey = RemoteHostScopedArtifactStore.pendingApprovalIDKey
        let receiptsKey = RemoteHostScopedArtifactStore.liveActivityReceiptsKey
        UserDefaults.standard.removeObject(forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: receiptsKey)
        RemotePairingIdentityStore.replaceAndPublish(
            "device-a",
            forCredential: "credential-a",
            runtimeIdentity: .paired("device-a")
        )
        let observationLock = NSLock()
        var deliveredEvent = false
        var trustedRouteAfterReplacement = false
        let notificationObserver = NotificationCenter.default.addObserver(
            forName: .codeIslandRemoteAttentionChanged,
            object: nil,
            queue: nil
        ) { notification in
            let requestID = notification.userInfo?["requestId"] as? String
            let kind = (notification.userInfo?["kind"] as? String).flatMap(
                RemoteAttentionKind.init(rawValue:)
            )
            let state = (notification.userInfo?["state"] as? String).flatMap(
                RemoteAttentionState.init(rawValue:)
            )
            let pairingDeviceID = notification.userInfo?["pairingDeviceID"] as? String
            let route = ScopedRemoteAttentionRoute.resolve(
                requestID: requestID,
                kind: kind,
                state: state,
                eventPairingDeviceID: pairingDeviceID,
                currentIdentity: RemotePairingIdentityStore.runtimeIdentity()
            )
            observationLock.lock()
            deliveredEvent = true
            trustedRouteAfterReplacement = route != nil
            observationLock.unlock()
        }
        defer {
            NotificationCenter.default.removeObserver(notificationObserver)
            RemotePairingIdentityStore.replaceAndPublish(
                nil,
                forCredential: nil,
                runtimeIdentity: .unpaired
            )
        }

        let validatedA = DispatchSemaphore(value: 0)
        let resumeA = DispatchSemaphore(value: 0)
        let transitionStarted = DispatchSemaphore(value: 0)
        let transitionFinished = DispatchSemaphore(value: 0)
        let processingFinished = DispatchSemaphore(value: 0)
        let issuedAt = Date().addingTimeInterval(-1)
        let envelope = RemoteAttentionPushEnvelope(
            eventID: "interleaved-a-event",
            kind: .approval,
            state: .pending,
            requestID: "interleaved-a-request",
            pairingDeviceID: "device-a",
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(600)
        )
        let delegate = CompanionAppDelegate()

        DispatchQueue.global(qos: .userInitiated).async {
            _ = delegate.processLegacy(
                envelope.payloadFields,
                afterPairingValidation: {
                    validatedA.signal()
                    _ = resumeA.wait(timeout: .now() + 2)
                }
            )
            processingFinished.signal()
        }
        XCTAssertEqual(validatedA.wait(timeout: .now() + 2), .success)

        DispatchQueue.global(qos: .userInitiated).async {
            transitionStarted.signal()
            RemotePairingIdentityStore.replaceAndPublish(
                "device-b",
                forCredential: "credential-b",
                runtimeIdentity: .paired("device-b")
            )
            transitionFinished.signal()
        }
        XCTAssertEqual(transitionStarted.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(transitionFinished.wait(timeout: .now() + 2), .success)
        resumeA.signal()
        XCTAssertEqual(processingFinished.wait(timeout: .now() + 2), .success)

        XCTAssertEqual(RemotePairingIdentityStore.runtimeIdentity(), .paired("device-b"))
        XCTAssertNil(UserDefaults.standard.object(forKey: pendingKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: receiptsKey))
        observationLock.lock()
        let observedDelivery = deliveredEvent
        let observedTrustedRoute = trustedRouteAfterReplacement
        observationLock.unlock()
        XCTAssertFalse(observedDelivery)
        XCTAssertFalse(observedTrustedRoute)
    }

    func testPairingCredentialChangeRequeuesClientMetadataRegistration() {
        var state = RemotePushRegistrationState()

        XCTAssertTrue(state.shouldRegisterClientMetadata(hasClientMetadata: true))
        state.markClientMetadataRegistered()
        XCTAssertFalse(state.shouldRegisterClientMetadata(hasClientMetadata: true))

        state.pairingCredentialDidChange()

        XCTAssertTrue(state.shouldRegisterClientMetadata(hasClientMetadata: true))
    }

    func testLiveActivityUpdateTokensStayScopedToTheirOriginalMac() {
        XCTAssertTrue(RemotePushRegistrationState.shouldRequeueHostScopedLiveActivityTokens(
            for: .restored
        ))
        XCTAssertFalse(RemotePushRegistrationState.shouldRequeueHostScopedLiveActivityTokens(
            for: .changed
        ))
    }

    func testCredentialChangeClearsHostScopedLiveActivityMailbox() {
        let suiteName = "CompanionPushPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["old-request": "old-route"], forKey: LiveActivityTokenMailbox.updateTokensKey)
        defaults.set(Data("old-receipt".utf8), forKey: LiveActivityTokenMailbox.receiptsKey)

        LiveActivityTokenMailbox.clearHostScopedArtifacts(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: LiveActivityTokenMailbox.updateTokensKey))
        XCTAssertNil(defaults.object(forKey: LiveActivityTokenMailbox.receiptsKey))
    }

    func testPairingReplacementQuarantinesHostStateBeforePersistingNewIdentity() {
        let suiteName = "CompanionPushPresentationTests.Transition.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        RemotePairingIdentityStore.store("device-a", forCredential: "credential-a", defaults: defaults)
        defaults.set(["old-request": "old-token"], forKey: RemoteHostScopedArtifactStore.liveActivityUpdateTokensKey)
        defaults.set(Data("old-receipt".utf8), forKey: RemoteHostScopedArtifactStore.liveActivityReceiptsKey)
        defaults.set("old-approval", forKey: RemoteHostScopedArtifactStore.pendingApprovalIDKey)
        defaults.set("old-question", forKey: RemoteHostScopedArtifactStore.pendingQuestionIDKey)
        defaults.set(UUID().uuidString, forKey: RemoteHostScopedArtifactStore.followedTaskIDKey)

        RemotePairingIdentityStore.replace(
            "device-b",
            forCredential: "credential-b",
            defaults: defaults
        )

        XCTAssertNil(defaults.object(forKey: RemoteHostScopedArtifactStore.liveActivityUpdateTokensKey))
        XCTAssertNil(defaults.object(forKey: RemoteHostScopedArtifactStore.liveActivityReceiptsKey))
        XCTAssertNil(defaults.object(forKey: RemoteHostScopedArtifactStore.pendingApprovalIDKey))
        XCTAssertNil(defaults.object(forKey: RemoteHostScopedArtifactStore.pendingQuestionIDKey))
        XCTAssertNil(defaults.object(forKey: RemoteHostScopedArtifactStore.followedTaskIDKey))
        XCTAssertNil(RemotePairingIdentityStore.current(forCredential: "credential-a", defaults: defaults))
        XCTAssertEqual(
            RemotePairingIdentityStore.current(forCredential: "credential-b", defaults: defaults),
            "device-b"
        )
    }

    func testColdLaunchWithoutProvenIdentityQuarantinesHostState() {
        let suiteName = "CompanionPushPresentationTests.ColdQuarantine.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        func seed() {
            defaults.set(["old-request": "old-token"], forKey: RemoteHostScopedArtifactStore.liveActivityUpdateTokensKey)
            defaults.set(Data("old-receipt".utf8), forKey: RemoteHostScopedArtifactStore.liveActivityReceiptsKey)
            defaults.set("old-approval", forKey: RemoteHostScopedArtifactStore.pendingApprovalIDKey)
            defaults.set(UUID().uuidString, forKey: RemoteHostScopedArtifactStore.followedTaskIDKey)
        }

        seed()
        XCTAssertTrue(RemoteHostScopedArtifactStore.quarantineIfUnowned(
            by: .credentialPresentButIdentityMissing,
            defaults: defaults
        ))
        XCTAssertNil(defaults.object(forKey: RemoteHostScopedArtifactStore.liveActivityUpdateTokensKey))
        XCTAssertNil(defaults.object(forKey: RemoteHostScopedArtifactStore.liveActivityReceiptsKey))
        XCTAssertNil(defaults.object(forKey: RemoteHostScopedArtifactStore.pendingApprovalIDKey))
        XCTAssertNil(defaults.object(forKey: RemoteHostScopedArtifactStore.followedTaskIDKey))

        seed()
        XCTAssertTrue(RemoteHostScopedArtifactStore.quarantineIfUnowned(by: .unpaired, defaults: defaults))
        XCTAssertNil(defaults.object(forKey: RemoteHostScopedArtifactStore.liveActivityUpdateTokensKey))

        seed()
        XCTAssertFalse(RemoteHostScopedArtifactStore.quarantineIfUnowned(
            by: .paired("device-b"),
            defaults: defaults
        ))
        XCTAssertNotNil(defaults.object(forKey: RemoteHostScopedArtifactStore.liveActivityUpdateTokensKey))
    }

    func testDeliveredAPNSTokenRemainsAvailableForNewPairingCredential() {
        let suiteName = "CompanionPushPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RemotePushTokenMailbox.store("a1b2c3", defaults: defaults)
        XCTAssertEqual(
            RemotePushTokenMailbox.registrationToken(
                republishCurrent: false,
                defaults: defaults
            ),
            "a1b2c3"
        )

        RemotePushTokenMailbox.acknowledge("a1b2c3", defaults: defaults)

        XCTAssertNil(RemotePushTokenMailbox.registrationToken(
            republishCurrent: false,
            defaults: defaults
        ))
        XCTAssertEqual(
            RemotePushTokenMailbox.registrationToken(
                republishCurrent: true,
                defaults: defaults
            ),
            "a1b2c3"
        )
    }

    func testAcceptedPushIsPresentedInForeground() {
        let options = CompanionAppDelegate.presentationOptions(for: .accepted)

        XCTAssertTrue(options.contains(.banner))
        XCTAssertNotEqual(options, [])
    }

    func testRejectedStalePushIsNotPresentedInForeground() {
        let options = CompanionAppDelegate.presentationOptions(for: .rejectedStale)

        XCTAssertEqual(options, [])
    }

    func testUnrecognizedPushFailsOpenForForegroundPresentation() {
        let options = CompanionAppDelegate.presentationOptions(for: .unrecognized)

        XCTAssertNotEqual(options, [])
    }

    func testAcceptedAndUnrecognizedPresentWhileRejectedStaleDoesNot() {
        let accepted = CompanionAppDelegate.presentationOptions(for: .accepted)
        let unrecognized = CompanionAppDelegate.presentationOptions(for: .unrecognized)
        let rejectedStale = CompanionAppDelegate.presentationOptions(for: .rejectedStale)

        XCTAssertEqual(accepted, unrecognized)
        XCTAssertNotEqual(rejectedStale, accepted)
        XCTAssertNotEqual(rejectedStale, unrecognized)
    }
}
