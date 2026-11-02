import Foundation

/// Keeps the user ID in step with RevenueCat's app user ID without depending on RevenueCat: the app hands over a
/// closure that reads it, and the SDK asks it at configure, when the app becomes active and before each event. Only a
/// changed ID is reported. Nil or empty means "not known right now" (e.g. RevenueCat isn't configured yet), never
/// "signed out": after `logOut` RevenueCat itself moves to a new anonymous ID, which is reported like any other.
final class RevenueCatLink {
    private let lock = NSLock()
    private var provider: (() -> String?)?
    private var reported: String?

    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return provider != nil
    }

    func connect(_ appUserId: @escaping () -> String?) {
        lock.lock(); provider = appUserId; reported = nil; lock.unlock()
    }

    func disconnect() {
        lock.lock(); provider = nil; reported = nil; lock.unlock()
    }

    /// The ID to report now: RevenueCat's current one if it changed since the last report, otherwise nil.
    func changedId() -> String? {
        lock.lock()
        let read = provider
        lock.unlock()
        // Read outside the lock: the closure calls into RevenueCat.
        guard let read, let raw = read() else { return nil }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.count <= Engine.maxUserId else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard provider != nil, id != reported else { return nil }
        reported = id
        return id
    }
}
