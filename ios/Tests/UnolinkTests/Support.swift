import Foundation
import XCTest
@testable import Unolink

/// The shared contract at the repo root (schemas, canned responses), found relative to this file.
enum Contract {
    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("contract")

    static func response(_ name: String) -> HTTPResponse {
        let data = try! Data(contentsOf: dir.appendingPathComponent("responses/\(name).json"))
        let root = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        return HTTPResponse(status: root["status"] as! Int, body: Payloads.json(root["body"]!))
    }

    static func assertValid(_ schemaName: String, _ json: String, file: StaticString = #filePath, line: UInt = #line) {
        let schemaData = try! Data(contentsOf: dir.appendingPathComponent("schemas/\(schemaName).schema.json"))
        let schema = try! JSONSerialization.jsonObject(with: schemaData) as! [String: Any]
        guard let instance = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed) else {
            return XCTFail("Not JSON: \(json)", file: file, line: line)
        }
        var errors: [String] = []
        SchemaCheck(root: schema).check(schema, instance, "$", &errors)
        if !errors.isEmpty { XCTFail("Doesn't match \(schemaName): \(errors.joined(separator: "; "))\n\(json)", file: file, line: line) }
    }
}

/// A small JSON Schema (2020-12) checker covering what contract/schemas use: type, required, properties, enum, const,
/// pattern, min/maxLength, minimum/maximum, min/maxItems, items, maxProperties, additionalProperties, anyOf, allOf,
/// if/then, local $ref, and
/// the uuid/date-time formats.
struct SchemaCheck {
    let root: [String: Any]

    func check(_ schema: [String: Any], _ value: Any, _ path: String, _ errors: inout [String]) {
        if let ref = schema["$ref"] as? String, ref.hasPrefix("#/$defs/"),
           let defs = root["$defs"] as? [String: Any], let target = defs[String(ref.dropFirst(8))] as? [String: Any] {
            check(target, value, path, &errors)
        }
        if let types = schema["type"] {
            let allowed = (types as? [String]) ?? [types as! String]
            if !allowed.contains(where: { isType($0, value) }) { errors.append("\(path): expected \(allowed), got \(value)") ; return }
        }
        if let options = schema["enum"] as? [Any], !options.contains(where: { equal($0, value) }) { errors.append("\(path): \(value) not in \(options)") }
        if let c = schema["const"], !equal(c, value) { errors.append("\(path): expected \(c)") }
        if let s = value as? String {
            if let min = schema["minLength"] as? Int, s.count < min { errors.append("\(path): too short") }
            if let max = schema["maxLength"] as? Int, s.count > max { errors.append("\(path): too long") }
            if let p = schema["pattern"] as? String, s.range(of: p, options: .regularExpression) == nil { errors.append("\(path): \"\(s)\" doesn't match \(p)") }
            if let f = schema["format"] as? String {
                if f == "uuid", UUID(uuidString: s) == nil { errors.append("\(path): not a uuid") }
                if f == "date-time", parseDate(s) == nil { errors.append("\(path): not a date-time") }
            }
        }
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            if let min = schema["minimum"] as? Double, n.doubleValue < min { errors.append("\(path): below \(min)") }
            if let max = schema["maximum"] as? Double, n.doubleValue > max { errors.append("\(path): above \(max)") }
        }
        if let a = value as? [Any] {
            if let min = schema["minItems"] as? Int, a.count < min { errors.append("\(path): fewer than \(min) items") }
            if let max = schema["maxItems"] as? Int, a.count > max { errors.append("\(path): more than \(max) items") }
            if let items = schema["items"] as? [String: Any] { for (i, v) in a.enumerated() { check(items, v, "\(path)[\(i)]", &errors) } }
        }
        if let o = value as? [String: Any] {
            for key in (schema["required"] as? [String]) ?? [] where o[key] == nil { errors.append("\(path).\(key): required") }
            if let max = schema["maxProperties"] as? Int, o.count > max { errors.append("\(path): more than \(max) properties") }
            let props = (schema["properties"] as? [String: Any]) ?? [:]
            for (key, v) in o {
                if let sub = props[key] as? [String: Any] { check(sub, v, "\(path).\(key)", &errors) }
                else if let extra = schema["additionalProperties"] as? [String: Any] { check(extra, v, "\(path).\(key)", &errors) }
                else if (schema["additionalProperties"] as? NSNumber)?.boolValue == false { errors.append("\(path).\(key): not allowed") }
            }
        }
        if let anyOf = schema["anyOf"] as? [[String: Any]] {
            let ok = anyOf.contains { sub in var e: [String] = []; check(sub, value, path, &e); return e.isEmpty }
            if !ok { errors.append("\(path): matches none of anyOf") }
        }
        for sub in (schema["allOf"] as? [[String: Any]]) ?? [] { check(sub, value, path, &errors) }
        if let cond = schema["if"] as? [String: Any], let then = schema["then"] as? [String: Any] {
            var e: [String] = []
            check(cond, value, path, &e)
            if e.isEmpty { check(then, value, path, &errors) }
        }
    }

    private func isType(_ type: String, _ v: Any) -> Bool {
        switch type {
        case "null": return v is NSNull
        case "boolean": return (v as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        case "integer": return (v as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue == $0.doubleValue.rounded() } ?? false
        case "number": return (v as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() } ?? false
        case "string": return v is String
        case "array": return v is [Any]
        case "object": return v is [String: Any]
        default: return false
        }
    }

    private func equal(_ a: Any, _ b: Any) -> Bool {
        if a is NSNull || b is NSNull { return a is NSNull && b is NSNull }
        return (a as? NSObject)?.isEqual(b) ?? false
    }

    private func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

struct Request {
    let method: String
    let path: String
    let body: String?
    var json: [String: Any] { Payloads.object(body)! }
}

/// Answers from a script; records every request. An empty script answers like a healthy server.
final class FakeServer: Transport {
    var requests: [Request] = []
    private var script: [HTTPResponse?] = []

    func next(_ responses: HTTPResponse...) { script.append(contentsOf: responses.map { Optional($0) }) }
    func networkError() { script.append(nil) }

    func send(method: String, path: String, body: String?) -> HTTPResponse? {
        requests.append(Request(method: method, path: path, body: body))
        if !script.isEmpty { return script.removeFirst() }
        if path == "/v1/install" { return Contract.response("install-unattributed") }
        let count = ((Payloads.object(body)?["events"] as? [Any])?.count) ?? 0
        return HTTPResponse(status: 202, body: "{\"accepted\":\(count),\"duplicates\":0,\"rejected\":[]}")
    }

    var paths: [String] { requests.map(\.path) }
    var eventNames: [String] {
        requests.filter { $0.path == "/v1/events" }.flatMap { ($0.json["events"] as! [[String: Any]]).map { $0["name"] as! String } }
    }
}

final class MemoryStore: KeyValueStore {
    var values: [String: String] = [:]
    func string(_ key: String) -> String? { values[key] }
    func set(_ key: String, _ value: String?) { values[key] = value }
}

final class MemoryQueue: QueueStore {
    var lines: [String] = []
    func load() -> [String] { lines }
    func save(_ lines: [String]) { self.lines = lines }
}

final class FakeClock: Clock {
    var time = Date(timeIntervalSince1970: 1_760_000_000)
    func now() -> Date { time }
}

/// Runs tasks immediately; delayed tasks wait for `advance`.
final class ManualScheduler: Scheduler {
    let clock: FakeClock
    private var delayed: [(at: Date, task: () -> Void)] = []
    init(clock: FakeClock) { self.clock = clock }

    func execute(_ task: @escaping () -> Void) { task() }
    func schedule(after milliseconds: Int, _ task: @escaping () -> Void) {
        delayed.append((clock.time.addingTimeInterval(Double(milliseconds) / 1000), task))
    }

    func advance(ms: Int) {
        let until = clock.time.addingTimeInterval(Double(ms) / 1000)
        while let i = delayed.indices.filter({ delayed[$0].at <= until }).min(by: { delayed[$0].at < delayed[$1].at }) {
            let next = delayed.remove(at: i)
            clock.time = max(clock.time, next.at)
            next.task()
        }
        clock.time = until
    }
}

final class QuietLogger: Logger {
    var errors: [String] = []
    func error(_ message: String) { errors.append(message) }
    func warn(_ message: String) {}
    func info(_ message: String) {}
    func debug(_ message: String) {}
}

final class Harness {
    let server: FakeServer
    let store: MemoryStore
    let queue: MemoryQueue
    let clock: FakeClock
    let scheduler: ManualScheduler
    let log = QuietLogger()
    let engine: Engine

    init(server: FakeServer = FakeServer(), store: MemoryStore = MemoryStore(), queue: MemoryQueue = MemoryQueue(), clock: FakeClock = FakeClock()) {
        self.server = server
        self.store = store
        self.queue = queue
        self.clock = clock
        scheduler = ManualScheduler(clock: clock)
        engine = Engine(
            device: DeviceInfo(platform: "ios", sdkName: "ios", sdkVersion: "0.1.0", osVersion: "26.0", appVersion: "1.9.5",
                               deviceClass: "phone", locale: "en-GB", isDebug: false),
            transport: server, store: store, queueStore: queue, scheduler: scheduler, clock: clock, log: log,
            runOnMain: { $0() }, random: { 0.5 })
    }

    /// A later app launch over the same disk state.
    func relaunch() -> Harness { Harness(server: server, store: store, queue: queue, clock: clock) }
}

/// Never runs anything: shows what is available synchronously.
final class DeferringScheduler: Scheduler {
    func execute(_ task: @escaping () -> Void) {}
    func schedule(after milliseconds: Int, _ task: @escaping () -> Void) {}
}
