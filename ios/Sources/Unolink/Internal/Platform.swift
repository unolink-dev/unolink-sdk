import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// SDK state lives in Application Support/Unolink, excluded from iCloud backup: a restored or new iPhone gets a new
/// install ID, like a reinstall. Plain files, not UserDefaults or the Keychain (the Keychain survives reinstalls).
enum Storage {
    static func directory() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        var dir = base.appendingPathComponent("Unolink", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }
}

final class FileKeyValueStore: KeyValueStore {
    private let url: URL
    private var values: [String: String]

    init(directory: URL) {
        url = directory.appendingPathComponent("state.json")
        values = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
    }

    func string(_ key: String) -> String? { values[key] }

    func set(_ key: String, _ value: String?) {
        values[key] = value
        if let data = try? JSONSerialization.data(withJSONObject: values) { try? data.write(to: url, options: .atomic) }
    }
}

final class FileQueueStore: QueueStore {
    private let url: URL

    init(directory: URL) { url = directory.appendingPathComponent("queue.jsonl") }

    func load() -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    func save(_ lines: [String]) { try? Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic) }
}

final class URLSessionTransport: Transport {
    private let baseURL: String
    private let apiKey: String
    private let userAgent: String
    private let session: URLSession

    init(baseURL: String, apiKey: String, userAgent: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.apiKey = apiKey
        self.userAgent = userAgent
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }

    func send(method: String, path: String, body: String?) -> HTTPResponse? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-Unolink-Key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        var result: HTTPResponse?
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, error in
            if error == nil, let http = response as? HTTPURLResponse {
                result = HTTPResponse(status: http.statusCode, body: data.map { String(decoding: $0, as: UTF8.self) })
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 30)
        return result
    }
}

final class DispatchScheduler: Scheduler {
    private let queue = DispatchQueue(label: "dev.unolink.sdk", qos: .utility)

    func execute(_ task: @escaping () -> Void) { queue.async(execute: task) }
    func schedule(after milliseconds: Int, _ task: @escaping () -> Void) {
        queue.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: task)
    }
}

struct SystemClock: Clock {
    func now() -> Date { Date() }
}

struct ConsoleLogger: Logger {
    let level: LogLevel
    private let log = OSLog(subsystem: "dev.unolink.sdk", category: "Unolink")

    func error(_ message: String) { write(.error, OSLogType.error, message) }
    func warn(_ message: String) { write(.warn, OSLogType.default, message) }
    func info(_ message: String) { write(.info, OSLogType.info, message) }
    func debug(_ message: String) { write(.debug, OSLogType.debug, message) }

    private func write(_ at: LogLevel, _ type: OSLogType, _ message: String) {
        guard level >= at else { return }
        os_log("[Unolink] %{public}@", log: log, type: type, message)
    }
}

enum AppleDevice {
    static func info(sdkName: String, sdkVersion: String, debug: Bool) -> DeviceInfo {
        #if canImport(UIKit) && !os(watchOS)
        let osVersion = UIDevice.current.systemVersion
        let tablet = UIDevice.current.userInterfaceIdiom == .pad
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let tablet = false
        #endif
        return DeviceInfo(
            platform: "ios",
            sdkName: sdkName,
            sdkVersion: sdkVersion,
            osVersion: osVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            deviceClass: tablet ? "tablet" : "phone",
            locale: Locale.preferredLanguages.first,
            // TestFlight (and Xcode) builds are never real users: test devices, whatever `debug` says.
            isDebug: debug || isTestBuild(receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent))
    }

    /// App Store installs carry a receipt named "receipt"; TestFlight and development builds a "sandboxReceipt". The
    /// receipt API is deprecated but still answers, and it's the only synchronous way to tell (AppTransaction is async).
    static func isTestBuild(receiptName: String?) -> Bool { receiptName == "sandboxReceipt" }
}

/// Foreground/background from UIKit's notifications. Background gets a short task so the last batch can go out.
final class Lifecycle {
    private var tokens: [NSObjectProtocol] = []

    init(engine: Engine) {
        #if canImport(UIKit) && !os(watchOS)
        // configure() often runs after the app is already active (React Native and Flutter call it from their own
        // code a moment after launch), so the first didBecomeActive is missed: catch up with the current state.
        DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .active { engine.onForeground() }
        }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
            engine.onForeground()
        })
        tokens.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            var task = UIBackgroundTaskIdentifier.invalid
            task = UIApplication.shared.beginBackgroundTask(withName: "Unolink flush") {
                UIApplication.shared.endBackgroundTask(task)
                task = .invalid
            }
            engine.onBackground()
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
            }
        })
        #endif
    }
}
