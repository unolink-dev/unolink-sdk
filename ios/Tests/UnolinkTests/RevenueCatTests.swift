import XCTest
@testable import Unolink

/// connectRevenueCat reads RevenueCat's app user ID through a closure and reports it only when it changed.
final class RevenueCatLinkTests: XCTestCase {
    func testReportsTheIdOnceThenOnlyChanges() {
        let link = RevenueCatLink()
        var current: String? = "$RCAnonymousID:abc"
        link.connect { current }
        XCTAssertEqual(link.changedId(), "$RCAnonymousID:abc")
        XCTAssertNil(link.changedId())
        current = "account-42"
        XCTAssertEqual(link.changedId(), "account-42")
        XCTAssertNil(link.changedId())
    }

    func testNilEmptyOrTooLongMeansUnknownNotSignedOut() {
        let link = RevenueCatLink()
        var current: String? = nil
        link.connect { current }
        XCTAssertNil(link.changedId())
        current = "  "
        XCTAssertNil(link.changedId())
        current = String(repeating: "x", count: Engine.maxUserId + 1)
        XCTAssertNil(link.changedId())
        current = " account-42 "
        XCTAssertEqual(link.changedId(), "account-42")
    }

    func testDisconnectStopsReadingAndReconnectReportsAgain() {
        let link = RevenueCatLink()
        link.connect { "a" }
        XCTAssertEqual(link.changedId(), "a")
        link.disconnect()
        XCTAssertFalse(link.isConnected)
        XCTAssertNil(link.changedId())
        link.connect { "a" }
        XCTAssertEqual(link.changedId(), "a")
    }
}

/// The public API over a test engine.
final class RevenueCatPublicAPITests: XCTestCase {
    private var h: Harness!

    override func setUp() {
        h = Harness()
        h.engine.start()
        h.server.requests.removeAll()
    }

    override func tearDown() {
        Unolink.disconnectRevenueCat()
        Unolink.engine = nil
    }

    private var installUserIds: [String?] {
        h.server.requests.filter { $0.path == "/v1/install" }.map { $0.json["userId"] as? String }
    }

    func testConnectReportsRevenueCatsIdAndAChangeGoesBeforeTheNextEvent() {
        Unolink.engine = h.engine
        var current = "$RCAnonymousID:guest"
        Unolink.connectRevenueCat { current }
        XCTAssertEqual(installUserIds, ["$RCAnonymousID:guest"])

        Unolink.signIn(method: "apple")  // same ID: not reported again
        XCTAssertEqual(installUserIds, ["$RCAnonymousID:guest"])

        current = "account-42"           // Purchases.logIn
        Unolink.paywallViewed(placement: "settings")
        XCTAssertEqual(installUserIds, ["$RCAnonymousID:guest", "account-42"])
        let lastEvents = h.server.requests.last { $0.path == "/v1/events" }!
        XCTAssertEqual(lastEvents.json["userId"] as? String, "account-42")
    }

    func testRevenueCatUserChangedReportsWithoutAnEvent() {
        Unolink.engine = h.engine
        var current = "$RCAnonymousID:guest"
        Unolink.connectRevenueCat { current }
        current = "account-42"
        Unolink.revenueCatUserChanged()
        XCTAssertEqual(installUserIds, ["$RCAnonymousID:guest", "account-42"])
        XCTAssertTrue(h.server.eventNames.isEmpty)
    }

    func testConnectingBeforeConfigureReportsOnceConfigured() {
        Unolink.connectRevenueCat { "$RCAnonymousID:guest" }
        Unolink.engine = h.engine
        Unolink.syncRevenueCat()  // what configure and app-active do
        XCTAssertEqual(installUserIds, ["$RCAnonymousID:guest"])
    }

    func testUnknownIdLeavesTheUserIdAlone() {
        Unolink.engine = h.engine
        Unolink.setUserId("account-42")
        Unolink.connectRevenueCat { nil }  // RevenueCat not configured yet
        Unolink.track("level_up")
        XCTAssertEqual(installUserIds, ["account-42"])
        XCTAssertEqual(h.store.string(Engine.keyUserId), "account-42")
    }

    func testSignUpSkippedSendsItsOwnEvent() {
        Unolink.engine = h.engine
        Unolink.signUpSkipped(properties: ["screen": "welcome"])
        Unolink.flush()
        let request = h.server.requests.last { $0.path == "/v1/events" }!
        Contract.assertValid("events-request", request.body!)
        let event = (request.json["events"] as! [[String: Any]]).last!
        XCTAssertEqual(event["name"] as? String, "sign_up_skipped")
        XCTAssertEqual((event["properties"] as? [String: Any])?["screen"] as? String, "welcome")
    }
}
