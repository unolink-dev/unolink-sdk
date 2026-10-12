import Foundation

/// How much the SDK writes to the console (prefix "[Unolink]").
@objc(UNLLogLevel)
public enum LogLevel: Int, Comparable {
    case none, error, warn, info, debug

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Optional settings for `Unolink.configure(apiKey:options:)`.
@objc(UNLOptions)
public final class UnolinkOptions: NSObject {
    /// Production. Use `https://api-uat.unolink.dev` while testing.
    @objc public static let defaultBaseURL = "https://api.unolink.dev"

    /// The SDK API.
    @objc public let baseURL: String
    /// How much the SDK logs.
    @objc public let logLevel: LogLevel
    /// Marks this install as a test device, so the dashboard leaves it out unless "Include test devices" is on. Pass
    /// `true` from debug builds, e.g. `#if DEBUG … #endif` (a compiled library can't see your app's build settings).
    @objc public let debug: Bool

    @objc public init(baseURL: String = UnolinkOptions.defaultBaseURL, logLevel: LogLevel = .warn, debug: Bool = false) {
        self.baseURL = baseURL
        self.logLevel = logLevel
        self.debug = debug
    }

    @objc public convenience override init() {
        self.init(baseURL: UnolinkOptions.defaultBaseURL, logLevel: .warn, debug: false)
    }
}

/// Where the app should take someone who just installed it from a Unolink link. On iPhone this is only delivered when
/// the install could be attributed with certainty; Apple offers no install referrer, and Unolink never fingerprints.
@objc(UNLDeepLink)
public final class UnolinkDeepLink: NSObject {
    /// The link's deep link as set in the dashboard, e.g. "/promo/3for2", or nil.
    @objc public let deepLink: String?
    /// The link's parameters.
    @objc public let params: [String: String]
    /// The campaign link's path (e.g. "tiktok"), or nil for the app's main link.
    @objc public let linkSlug: String?
    /// The click that led to the install.
    @objc public let clickId: String

    init(deepLink: String?, params: [String: String], linkSlug: String?, clickId: String) {
        self.deepLink = deepLink
        self.params = params
        self.linkSlug = linkSlug
        self.clickId = clickId
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? UnolinkDeepLink else { return false }
        return o.deepLink == deepLink && o.params == params && o.linkSlug == linkSlug && o.clickId == clickId
    }

    public override var hash: Int { clickId.hashValue }
}
