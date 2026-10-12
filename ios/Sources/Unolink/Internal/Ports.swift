import Foundation

/// An HTTP answer. Network failures are reported as nil instead.
struct HTTPResponse {
    let status: Int
    let body: String?
}

protocol Transport {
    /// Blocking; called only from the SDK's own queue. Nil means a network error.
    func send(method: String, path: String, body: String?) -> HTTPResponse?
}

/// Small persistent key/value store for SDK state (install ID, flags). Excluded from iCloud backup.
protocol KeyValueStore: AnyObject {
    func string(_ key: String) -> String?
    func set(_ key: String, _ value: String?)
}

extension KeyValueStore {
    func bool(_ key: String) -> Bool { string(key) == "true" }
    func setBool(_ key: String, _ value: Bool) { set(key, value ? "true" : nil) }
}

/// Where queued events survive app restarts (one JSON object per line).
protocol QueueStore: AnyObject {
    func load() -> [String]
    func save(_ lines: [String])
}

/// The SDK's single serial queue. All engine state is touched only from it.
protocol Scheduler {
    func execute(_ task: @escaping () -> Void)
    func schedule(after milliseconds: Int, _ task: @escaping () -> Void)
}

protocol Clock {
    func now() -> Date
}

protocol Logger {
    func error(_ message: String)
    func warn(_ message: String)
    func info(_ message: String)
    func debug(_ message: String)
}

/// Facts about the app and device that go into /v1/install. Nothing here identifies a person or the device.
struct DeviceInfo {
    let platform: String
    let sdkName: String
    let sdkVersion: String
    let osVersion: String?
    let appVersion: String?
    let deviceClass: String?
    let locale: String?
    let isDebug: Bool
}
