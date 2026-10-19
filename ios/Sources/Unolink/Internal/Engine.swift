import Foundation

/// Everything the SDK does, without UIKit: install registration, the event queue, batching, retries and the deferred
/// deep link. Runs only on `scheduler`'s serial queue; public entry points hop onto it. Same rules as the Android SDK
/// (contract/README.md): /v1/install first and retried until it succeeds; batches of up to 100 removed on 202; 409
/// re-registers; 401/403 stop until the next launch; network errors, 408, 429 and 5xx back off (1 s to 5 min, jitter).
final class Engine {
    static let maxQueue = 1000
    static let batchSize = 100
    static let flushAt = 20
    static let flushIntervalMs = 15_000
    static let sessionGap: TimeInterval = 30 * 60
    static let minBackoffMs = 1_000
    static let maxBackoffMs = 5 * 60_000
    static let maxUserId = 256

    static let keyInstallId = "install_id"
    static let keyRegistered = "install_registered"
    static let keyOptedOut = "opted_out"
    static let keyDeepLinkDone = "deep_link_done"
    static let keyUserId = "user_id"

    private let device: DeviceInfo
    private let transport: Transport
    private let store: KeyValueStore
    private let queueStore: QueueStore
    private let scheduler: Scheduler
    private let clock: Clock
    private let log: Logger
    private let runOnMain: (@escaping () -> Void) -> Void
    private let random: () -> Double

    private var queue: [String] = []
    private var installId: String?
    private var registered = false
    private var stopped = false
    private var sdkDisabled = false
    private var optedOut = false
    private var inFlight = false
    private var backoffMs = 0
    private var retryScheduled = false
    private var reRegistrations = 0
    private var foreground = false
    private var timerRunning = false
    private var backgroundAt: Date?
    private var pendingDeepLink: UnolinkDeepLink?
    private let listenerLock = NSLock()
    private var _listener: ((UnolinkDeepLink) -> Void)?
    private let idLock = NSLock()
    private var _publicInstallId: String?

    var publicInstallId: String? {
        idLock.lock(); defer { idLock.unlock() }
        return _publicInstallId
    }

    init(device: DeviceInfo, transport: Transport, store: KeyValueStore, queueStore: QueueStore, scheduler: Scheduler,
         clock: Clock, log: Logger, runOnMain: @escaping (@escaping () -> Void) -> Void, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.device = device
        self.transport = transport
        self.store = store
        self.queueStore = queueStore
        self.scheduler = scheduler
        self.clock = clock
        self.log = log
        self.runOnMain = runOnMain
        self.random = random
    }

    /// Cold start. iOS has no install referrer, so the install is registered straight away. The install ID is loaded
    /// (or created) synchronously, so `Unolink.installId` is available as soon as `configure` returns.
    func start() {
        let existing = store.string(Self.keyInstallId)
        let id = existing ?? UUID().uuidString.lowercased()
        if existing == nil { store.set(Self.keyInstallId, id) }
        idLock.lock(); _publicInstallId = id; idLock.unlock()

        scheduler.execute { [self] in
            optedOut = store.bool(Self.keyOptedOut)
            queue = Array(queueStore.load().suffix(Self.maxQueue))
            registered = existing != nil && store.bool(Self.keyRegistered)
            installId = id
            if existing == nil { enqueue("first_open", nil, nil) }
            if optedOut {
                log.info("Tracking is off for this install (setEnabled(false)).")
                return
            }
            enqueue("session_start", nil, nil)
            if registered { flush() } else { register() }
        }
    }

    func setListener(_ listener: ((UnolinkDeepLink) -> Void)?) {
        listenerLock.lock(); _listener = listener; listenerLock.unlock()
        scheduler.execute { [self] in
            if let link = pendingDeepLink { deliver(link) }
        }
    }

    func track(_ name: String, properties: [String: Any]?, revenue: (amount: String, currency: String)?) {
        scheduler.execute { [self] in
            guard !optedOut else { return }
            guard Payloads.isValidName(name) else {
                log.error("Event name \"\(name)\" is invalid: start with a letter; letters, digits, _ and . only; at most 64.")
                return
            }
            enqueue(name, Payloads.properties(properties, log: log), revenue)
            if queue.count >= Self.flushAt { flush() }
        }
    }

    func flushNow() { scheduler.execute { [self] in flush() } }

    func setUserId(_ userId: String?) {
        scheduler.execute { [self] in
            let clean = userId?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let c = clean, c.count > Self.maxUserId {
                log.error("setUserId(): at most \(Self.maxUserId) characters; ignored.")
                return
            }
            let value = clean?.isEmpty == false ? clean : nil
            guard value != store.string(Self.keyUserId) else { return }
            store.set(Self.keyUserId, value)
            // Tell the server now (the install request is idempotent and carries the user ID), so RevenueCat purchases
            // join this install even if no other event follows. Persisted, so it also happens if the app is closed first.
            if registered {
                registered = false
                store.setBool(Self.keyRegistered, false)
                flush()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        scheduler.execute { [self] in
            optedOut = !enabled
            store.setBool(Self.keyOptedOut, optedOut)
            if optedOut {
                queue.removeAll()
                persist()
                log.info("Tracking turned off: queued events deleted, nothing more will be sent.")
            } else {
                log.info("Tracking turned on.")
                if registered { flush() } else { register() }
            }
        }
    }

    func onForeground() {
        scheduler.execute { [self] in
            foreground = true
            let now = clock.now()
            if let bg = backgroundAt, now.timeIntervalSince(bg) >= Self.sessionGap, !optedOut { enqueue("session_start", nil, nil) }
            backgroundAt = nil
            if !timerRunning {
                timerRunning = true
                scheduler.schedule(after: Self.flushIntervalMs) { [weak self] in self?.tick() }
            }
        }
    }

    func onBackground() {
        scheduler.execute { [self] in
            foreground = false
            backgroundAt = clock.now()
            if !optedOut { enqueue("app_background", nil, nil) }
            flush()
        }
    }

    private func tick() {
        guard foreground else {
            timerRunning = false
            return
        }
        flush()
        scheduler.schedule(after: Self.flushIntervalMs) { [weak self] in self?.tick() }
    }

    private func enqueue(_ name: String, _ properties: [String: Any]?, _ revenue: (amount: String, currency: String)?) {
        guard !sdkDisabled else { return }
        queue.append(Payloads.event(id: UUID().uuidString.lowercased(), name: name, at: clock.now(), properties: properties, revenue: revenue))
        while queue.count > Self.maxQueue {
            queue.removeFirst()
            log.warn("Event queue is full (\(Self.maxQueue)); dropped the oldest event.")
        }
        persist()
    }

    private func persist() { queueStore.save(queue) }

    private func register() {
        guard let id = installId, !stopped, !optedOut, !inFlight, !registered else { return }
        inFlight = true
        let response = transport.send(method: "POST", path: "/v1/install",
                                      body: Payloads.install(installId: id, device: device, userId: store.string(Self.keyUserId)))
        inFlight = false
        guard let r = response else { return scheduleRetry() }
        if (200...299).contains(r.status) {
            registered = true
            store.setBool(Self.keyRegistered, true)
            backoffMs = 0
            if let link = Payloads.deepLink(fromInstall: r.body) { offerDeepLink(link) }
            flush()
        } else {
            handleFailure(r, batchSize: 0)
        }
    }

    private func flush() {
        guard !stopped, !optedOut, !inFlight, !retryScheduled else { return }
        guard registered else { return register() }
        guard !queue.isEmpty, let id = installId else { return }
        let batch = Array(queue.prefix(Self.batchSize))
        inFlight = true
        let response = transport.send(method: "POST", path: "/v1/events",
                                      body: Payloads.events(installId: id, events: batch, userId: store.string(Self.keyUserId)))
        inFlight = false
        guard let r = response else { return scheduleRetry() }
        if (200...299).contains(r.status) {
            queue.removeFirst(batch.count)
            persist()
            backoffMs = 0
            reRegistrations = 0
            for rejected in Payloads.rejected(r.body) {
                log.warn("Event rejected (\(rejected["code"] as? String ?? "")): \(rejected["message"] as? String ?? "")")
            }
            if !queue.isEmpty { flush() }
        } else {
            handleFailure(r, batchSize: batch.count)
        }
    }

    private func handleFailure(_ r: HTTPResponse, batchSize: Int) {
        let code = Payloads.problemCode(r.body)
        switch r.status {
        case 409 where code == "install_required" && reRegistrations >= 2:
            scheduleRetry()
        case 409 where code == "install_required":
            reRegistrations += 1
            log.info("Server doesn't know this install yet; registering it again.")
            registered = false
            store.setBool(Self.keyRegistered, false)
            register()
        case 401:
            stopped = true
            log.error("Invalid SDK key (401). Check the key in Unolink → your app → Settings → API keys. Nothing is sent until the next launch.")
        case 403:
            stopped = true
            sdkDisabled = true
            queue.removeAll()
            persist()
            log.error("The SDK isn't included in this app's Unolink plan (403 \(code ?? "")). Events are not recorded.")
        case 408, 429, 500...:
            scheduleRetry()
        default:
            // 400 and other client errors never succeed on retry: drop what was sent.
            log.error("Unolink rejected a request (\(r.status) \(code ?? "")); dropped it.")
            if batchSize > 0 {
                queue.removeFirst(min(batchSize, queue.count))
                persist()
            } else {
                stopped = true // a malformed install request won't fix itself
            }
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        backoffMs = backoffMs == 0 ? Self.minBackoffMs : min(backoffMs * 2, Self.maxBackoffMs)
        let delay = Int(Double(backoffMs) * (0.5 + random() / 2))
        retryScheduled = true
        log.debug("Retrying in \(delay) ms.")
        scheduler.schedule(after: delay) { [weak self] in
            guard let self = self else { return }
            self.retryScheduled = false
            if self.registered { self.flush() } else { self.register() }
        }
    }

    private func offerDeepLink(_ link: UnolinkDeepLink) {
        guard !store.bool(Self.keyDeepLinkDone), pendingDeepLink == nil else { return }
        pendingDeepLink = link
        deliver(link)
    }

    private func deliver(_ link: UnolinkDeepLink) {
        listenerLock.lock(); let listener = _listener; listenerLock.unlock()
        guard let l = listener, !store.bool(Self.keyDeepLinkDone) else { return }
        store.setBool(Self.keyDeepLinkDone, true)
        pendingDeepLink = nil
        runOnMain { l(link) }
    }
}
