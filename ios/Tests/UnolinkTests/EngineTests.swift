import XCTest
@testable import Unolink

final class EngineTests: XCTestCase {
    func testFirstLaunchRegistersThenSendsEventsMatchingTheContract() {
        let h = Harness()
        h.engine.setUserId("user-123")
        h.engine.start()

        XCTAssertEqual(h.server.paths, ["/v1/install", "/v1/events"])
        Contract.assertValid("install-request", h.server.requests[0].body!)
        XCTAssertEqual(h.server.requests[0].json["platform"] as? String, "ios")
        XCTAssertEqual(h.server.requests[0].json["userId"] as? String, "user-123")
        XCTAssertNil(h.server.requests[0].json["playReferrer"])
        Contract.assertValid("events-request", h.server.requests[1].body!)
        XCTAssertEqual(h.server.eventNames, ["first_open", "session_start"])
        XCTAssertTrue(h.queue.lines.isEmpty)
    }

    func testUnattributedInstallDeliversNoDeepLinkButAnAttributedOneDoesOnce() {
        let h = Harness()
        var received: [UnolinkDeepLink] = []
        h.engine.setListener { received.append($0) }
        h.engine.start()
        XCTAssertTrue(received.isEmpty)

        let h2 = Harness()
        h2.server.next(Contract.response("install-attributed"))
        h2.engine.start()
        h2.engine.setListener { received.append($0) }
        h2.engine.setListener { received.append($0) }
        XCTAssertEqual(received, [UnolinkDeepLink(deepLink: "/promo/3for2", params: ["offer": "3for2"], linkSlug: "tiktok", clickId: "clk_01JA9Q3F6Z8W2K4N7R5T1V0X3Y")])
    }

    func testEventsWaitForRegistrationAndSurviveRestartsWhileOffline() {
        let h = Harness()
        h.server.networkError()
        h.engine.start()
        h.engine.track("level_up", properties: ["level": 3], revenue: nil)
        XCTAssertEqual(h.server.paths, ["/v1/install"])
        XCTAssertEqual(h.queue.lines.count, 3)

        let later = h.relaunch()
        later.engine.start()
        XCTAssertEqual(later.server.eventNames, ["first_open", "session_start", "level_up", "session_start"])
    }

    func testNetworkErrorsBackOffAndRetry() {
        let h = Harness()
        h.engine.start()
        h.server.requests.removeAll()
        h.server.networkError()
        h.server.networkError()
        h.engine.track("a", properties: nil, revenue: nil)
        h.engine.flushNow()
        XCTAssertEqual(h.server.requests.count, 1)
        h.scheduler.advance(ms: 750)
        XCTAssertEqual(h.server.requests.count, 2)
        h.scheduler.advance(ms: 1_500)
        XCTAssertEqual(h.server.requests.count, 3)
        XCTAssertTrue(h.queue.lines.isEmpty)
    }

    func testInstallRequiredRegistersAgainAndResendsTheBatch() {
        let h = Harness()
        h.engine.start()
        h.server.requests.removeAll()
        h.server.next(Contract.response("problem-install-required"))
        h.engine.track("paywall_viewed", properties: nil, revenue: nil)
        h.engine.flushNow()
        XCTAssertEqual(h.server.paths, ["/v1/events", "/v1/install", "/v1/events"])
        XCTAssertEqual(h.server.requests[0].body, h.server.requests[2].body)
    }

    func testInvalidKeyStopsButKeepsEvents() {
        let h = Harness()
        h.server.next(Contract.response("problem-invalid-key"))
        h.engine.start()
        h.engine.track("a", properties: nil, revenue: nil)
        h.engine.flushNow()
        XCTAssertEqual(h.server.requests.count, 1)
        XCTAssertEqual(h.queue.lines.count, 3)
        XCTAssertTrue(h.log.errors.contains { $0.contains("Invalid SDK key") })
    }

    func testSdkDisabledStopsAndKeepsNothing() {
        let h = Harness()
        h.server.next(Contract.response("problem-sdk-disabled"))
        h.engine.start()
        h.engine.track("a", properties: nil, revenue: nil)
        XCTAssertEqual(h.server.requests.count, 1)
        XCTAssertTrue(h.queue.lines.isEmpty)
    }

    func testValidationErrorsAndRejectedEventsAreNotRetried() {
        let h = Harness()
        h.engine.start()
        h.server.next(Contract.response("problem-validation"))
        h.engine.track("a", properties: nil, revenue: nil)
        h.engine.flushNow()
        XCTAssertTrue(h.queue.lines.isEmpty)
        h.server.next(Contract.response("events-some-rejected"))
        h.engine.track("b", properties: nil, revenue: nil)
        h.engine.flushNow()
        XCTAssertTrue(h.queue.lines.isEmpty)
    }

    func testPurchaseCarriesAnExactDecimalAmount() {
        let h = Harness()
        h.engine.start()
        h.server.requests.removeAll()
        h.engine.track("purchase", properties: ["product_id": "pro_yearly", "trial": false, "price": 49.99], revenue: (Payloads.amount(Decimal(string: "49.990")!)!, "usd"))
        h.engine.flushNow()
        let body = h.server.requests.last!.body!
        Contract.assertValid("events-request", body)
        let event = (h.server.requests.last!.json["events"] as! [[String: Any]])[0]
        XCTAssertEqual((event["revenue"] as! [String: String])["amount"], "49.99")
        XCTAssertEqual((event["revenue"] as! [String: String])["currency"], "USD")
        XCTAssertEqual((event["properties"] as! [String: Any])["trial"] as? Bool, false)
    }

    func testInvalidNamesAreRefusedLocally() {
        let h = Harness()
        h.engine.start()
        h.server.requests.removeAll()
        h.engine.track("bad name", properties: nil, revenue: nil)
        h.engine.flushNow()
        XCTAssertTrue(h.server.requests.isEmpty)
    }

    func testBatchesHoldAtMost100Events() {
        let h = Harness()
        h.server.networkError()
        h.engine.start()
        for i in 0..<248 { h.engine.track("e\(i)", properties: nil, revenue: nil) }
        let again = h.relaunch()
        again.engine.start()
        let sizes = again.server.requests.filter { $0.path == "/v1/events" }.map { ($0.json["events"] as! [Any]).count }
        XCTAssertEqual(sizes, [100, 100, 51])
    }

    func testQueueIsCappedDroppingTheOldest() {
        let h = Harness()
        h.server.networkError()
        h.engine.start()
        for i in 0..<(Engine.maxQueue + 50) { h.engine.track("e\(i)", properties: nil, revenue: nil) }
        XCTAssertEqual(h.queue.lines.count, Engine.maxQueue)
        XCTAssertTrue(h.queue.lines.last!.contains("\"e\(Engine.maxQueue + 49)\""))
    }

    func testOptingOutDeletesTheQueueAndSendsNothingAcrossLaunches() {
        let h = Harness()
        h.server.networkError()
        h.engine.start()
        h.engine.setEnabled(false)
        h.engine.track("a", properties: nil, revenue: nil)
        XCTAssertTrue(h.queue.lines.isEmpty)
        let later = h.relaunch()
        later.server.requests.removeAll()
        later.engine.start()
        later.engine.track("b", properties: nil, revenue: nil)
        later.engine.flushNow()
        XCTAssertTrue(later.server.requests.isEmpty)
    }

    func testANewSessionStartsAfter30MinutesInTheBackground() {
        let h = Harness()
        h.engine.start()
        h.engine.onForeground()
        h.engine.onBackground()
        h.clock.time.addTimeInterval(5 * 60)
        h.engine.onForeground()
        h.engine.onBackground()
        h.clock.time.addTimeInterval(31 * 60)
        h.engine.onForeground()
        h.engine.flushNow()
        XCTAssertEqual(h.server.eventNames, ["first_open", "session_start", "app_background", "app_background", "session_start"])
    }

    func testInstallIdIsAvailableAsSoonAsStartReturns() {
        let h = Harness()
        let deferred = DeferringScheduler()
        let engine = Engine(device: DeviceInfo(platform: "ios", sdkName: "ios", sdkVersion: "0.1.0", osVersion: nil, appVersion: nil,
                                               deviceClass: nil, locale: nil, isDebug: false),
                            transport: h.server, store: h.store, queueStore: h.queue, scheduler: deferred, clock: h.clock, log: h.log,
                            runOnMain: { $0() })
        engine.start()
        XCTAssertNotNil(engine.publicInstallId, "before the queue has run anything")
        XCTAssertTrue(h.server.requests.isEmpty)
    }

    func testInstallIdIsRandomStableAndNotResent() {
        let h = Harness()
        h.engine.start()
        let id = h.engine.publicInstallId!
        XCTAssertNotNil(UUID(uuidString: id))
        let later = h.relaunch()
        later.server.requests.removeAll()
        later.engine.start()
        XCTAssertEqual(later.engine.publicInstallId, id)
        XCTAssertFalse(later.server.paths.contains("/v1/install"))
    }

    func testServerErrorsAreRetriedNotDropped() {
        let h = Harness()
        h.engine.start()
        h.server.next(Contract.response("server-error"), HTTPResponse(status: 429, body: nil))
        h.engine.track("a", properties: nil, revenue: nil)
        h.engine.flushNow()
        XCTAssertFalse(h.queue.lines.isEmpty)
        h.scheduler.advance(ms: 10_000)
        XCTAssertTrue(h.queue.lines.isEmpty)
    }

    func testANewUserIdIsSentAtOnceEvenWithoutEvents() {
        let h = Harness()
        h.engine.start()
        h.server.requests.removeAll()
        h.engine.setUserId("user-9")
        XCTAssertEqual(h.server.paths, ["/v1/install"])
        XCTAssertEqual(h.server.requests[0].json["userId"] as? String, "user-9")
        h.engine.setUserId("user-9")
        XCTAssertEqual(h.server.requests.count, 1)
    }

    func testUserIdCanBeCleared() {
        let h = Harness()
        h.engine.setUserId("u1")
        h.engine.start()
        h.engine.setUserId(nil)
        h.engine.track("a", properties: nil, revenue: nil)
        h.engine.flushNow()
        XCTAssertNil(h.server.requests.last!.json["userId"])
    }
}

final class PayloadsTests: XCTestCase {
    func testAmountsAreExactDecimalStrings() {
        XCTAssertEqual(Payloads.amount(Decimal(string: "49.990")!), "49.99")
        XCTAssertEqual(Payloads.amount(Decimal(string: "1E+2")!), "100")
        XCTAssertEqual(Payloads.amount(Decimal(string: "0.000001")!), "0.000001")
        XCTAssertNil(Payloads.amount(Decimal(string: "0.0000001")!))
        XCTAssertNil(Payloads.amount(Decimal(-1)))
    }

    func testTimestampsAreUtcIso8601WithMillis() {
        XCTAssertEqual(Payloads.timestamp(Date(timeIntervalSince1970: 1_760_000_000)), "2025-10-09T08:53:20.000Z")
    }

    func testPropertiesKeepOnlyFlatValues() {
        let p = Payloads.properties(["s": String(repeating: "x", count: 300), "n": 3, "b": true, "list": [1], "nan": Double.nan], log: QuietLogger())!
        XCTAssertEqual(Set(p.keys), ["s", "n", "b"])
        XCTAssertEqual((p["s"] as! String).count, 200)
    }

    /// React Native and Flutter hand numbers over as NSNumber; 0 and 1 must stay numbers (Swift would happily read them
    /// as Bool), or onboardingStep(index: 0/1) arrives as false/true and the server refuses it.
    func testBridgedNumbersZeroAndOneStayNumbers() {
        let p = Payloads.properties(["zero": NSNumber(value: 0), "one": NSNumber(value: 1.0), "yes": NSNumber(value: true), "native": true], log: QuietLogger())!
        let json = String(data: try! JSONSerialization.data(withJSONObject: p, options: .sortedKeys), encoding: .utf8)!
        XCTAssertEqual(json, #"{"native":true,"one":1,"yes":true,"zero":0}"#)

        let h = Harness()
        h.engine.start()
        h.server.requests.removeAll()
        h.engine.track("onboarding_step", properties: ["step": "welcome", "index": NSNumber(value: 0.0)], revenue: nil)
        h.engine.flushNow()
        Contract.assertValid("events-request", h.server.requests.last!.body!)
    }
}
