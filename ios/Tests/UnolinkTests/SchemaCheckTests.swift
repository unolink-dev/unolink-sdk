import XCTest
@testable import Unolink

/// The schema checker must actually catch violations, or the contract assertions prove nothing.
final class SchemaCheckTests: XCTestCase {
    private func errors(_ schemaName: String, _ json: String) -> [String] {
        let data = try! Data(contentsOf: Contract.dir.appendingPathComponent("schemas/\(schemaName).schema.json"))
        let schema = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        var errors: [String] = []
        SchemaCheck(root: schema).check(schema, try! JSONSerialization.jsonObject(with: Data(json.utf8)), "$", &errors)
        return errors
    }

    func testCatchesViolations() {
        XCTAssertFalse(errors("install-request", #"{"installId":"x","platform":"ios","sdk":{"name":"ios","version":"1"}}"#).isEmpty, "bad uuid")
        XCTAssertFalse(errors("install-request", #"{"installId":"6b1f0e1c-1b1a-4c1a-9b1a-1b1a1b1a1b1a","platform":"web","sdk":{"name":"ios","version":"1"}}"#).isEmpty, "bad enum")
        XCTAssertFalse(errors("events-request", #"{"installId":"6b1f0e1c-1b1a-4c1a-9b1a-1b1a1b1a1b1a","events":[{"id":"6b1f0e1c-1b1a-4c1a-9b1a-1b1a1b1a1b1a","name":"purchase","timestamp":"2026-10-12T10:00:00.000Z"}]}"#).isEmpty, "purchase without revenue")
        XCTAssertFalse(errors("events-request", #"{"installId":"6b1f0e1c-1b1a-4c1a-9b1a-1b1a1b1a1b1a","events":[]}"#).isEmpty, "empty batch")
        XCTAssertTrue(errors("events-request", #"{"installId":"6b1f0e1c-1b1a-4c1a-9b1a-1b1a1b1a1b1a","events":[{"id":"6b1f0e1c-1b1a-4c1a-9b1a-1b1a1b1a1b1a","name":"purchase","timestamp":"2026-10-12T10:00:00.000Z","revenue":{"amount":"4.99","currency":"USD"}}]}"#).isEmpty, "valid purchase")
        func event(_ name: String, _ properties: String) -> String {
            #"{"installId":"6b1f0e1c-1b1a-4c1a-9b1a-1b1a1b1a1b1a","events":[{"id":"6b1f0e1c-1b1a-4c1a-9b1a-1b1a1b1a1b1a","name":""# + name
                + #"","timestamp":"2026-10-12T10:00:00.000Z","properties":"# + properties + "}]}"
        }
        XCTAssertTrue(errors("events-request", event("onboarding_step", #"{"step":"goal","index":0,"flow":"v2"}"#)).isEmpty, "valid step")
        XCTAssertFalse(errors("events-request", event("onboarding_step", #"{"index":0}"#)).isEmpty, "step without step")
        XCTAssertFalse(errors("events-request", event("onboarding_skipped", #"{"step":"goal","email":"a@b.c"}"#)).isEmpty, "extra property")
        XCTAssertFalse(errors("events-request", event("onboarding_step", #"{"step":"goal","index":-1}"#)).isEmpty, "negative index")
        XCTAssertTrue(errors("events-request", event("level_up", #"{"email":"a@b.c"}"#)).isEmpty, "custom events are free-form")
    }
}
