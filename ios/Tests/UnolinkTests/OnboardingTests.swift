import XCTest
@testable import Unolink

/// onboardingStep / onboardingSkipped send only step, index and flow, in a batch the contract accepts.
final class OnboardingTests: XCTestCase {
    private func send(_ name: String, _ properties: [String: Any]) -> [String: Any] {
        let h = Harness()
        h.engine.start()
        h.server.requests.removeAll()
        h.engine.track(name, properties: properties, revenue: nil)
        h.engine.flushNow()
        let body = h.server.requests.last!.body!
        Contract.assertValid("events-request", body)
        let event = (h.server.requests.last!.json["events"] as! [[String: Any]])[0]
        XCTAssertEqual(event["name"] as? String, name)
        return event["properties"] as! [String: Any]
    }

    func testStepCarriesStepIndexAndFlow() {
        let properties = send("onboarding_step", Unolink.onboarding("goal", 1, "v2"))
        XCTAssertEqual(Set(properties.keys), ["step", "index", "flow"])
        XCTAssertEqual(properties["step"] as? String, "goal")
        XCTAssertEqual(properties["index"] as? Int, 1)
        XCTAssertEqual(properties["flow"] as? String, "v2")
    }

    func testMissingIndexAndFlowAreLeftOut() {
        let properties = send("onboarding_step", Unolink.onboarding("goal", nil, nil))
        XCTAssertEqual(Set(properties.keys), ["step"])
    }

    func testSkippedHasTheSameShape() {
        let properties = send("onboarding_skipped", Unolink.onboarding("notifications", 3, nil))
        XCTAssertEqual(Set(properties.keys), ["step", "index"])
        XCTAssertEqual(properties["step"] as? String, "notifications")
    }
}

/// TestFlight and Xcode builds carry a sandbox receipt; only App Store installs are real users.
final class TestBuildTests: XCTestCase {
    func testOnlyTheSandboxReceiptIsATestBuild() {
        XCTAssertTrue(AppleDevice.isTestBuild(receiptName: "sandboxReceipt"))
        XCTAssertFalse(AppleDevice.isTestBuild(receiptName: "receipt"))
        XCTAssertFalse(AppleDevice.isTestBuild(receiptName: nil))
    }
}
