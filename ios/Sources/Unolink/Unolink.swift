import Foundation

/// Unolink: which link or ad brings installs, onboarding, paywall views, trials and purchases.
///
/// Call `configure` once, early (in `App.init` or `application(_:didFinishLaunchingWithOptions:)`). Everything else is
/// safe from any thread, never blocks, and never throws: events are queued on disk and sent in the background.
///
/// ```swift
/// Unolink.configure(apiKey: "ulk_…")
/// Unolink.paywallViewed(placement: "onboarding")
/// Unolink.purchase(amount: Decimal(string: "49.99")!, currency: "USD", productId: "pro_yearly")
/// ```
@objc(Unolink)
public final class Unolink: NSObject {
    /// This SDK's version.
    @objc(sdkVersion) public static let version = "0.3.0"

    private static let lock = NSLock()
    private static var engine: Engine?
    private static var lifecycle: Lifecycle?
    private static var pendingHandler: ((UnolinkDeepLink) -> Void)?

    private override init() {}

    /// Starts the SDK: registers the install on first launch, then reports sessions and your events.
    /// - Parameter apiKey: The app's SDK key from Unolink (dashboard → your app → Settings → API keys). It is fine to ship it in the app.
    @objc(configureWithApiKey:options:)
    public static func configure(apiKey: String, options: UnolinkOptions = UnolinkOptions()) {
        configure(apiKey: apiKey, options: options, sdkName: "ios", sdkVersion: version)
    }

    /// For the React Native and Flutter packages, which report their own name and version.
    @objc(configureWithApiKey:options:sdkName:sdkVersion:)
    public static func configure(apiKey: String, options: UnolinkOptions, sdkName: String, sdkVersion: String) {
        lock.lock()
        defer { lock.unlock() }
        let log = ConsoleLogger(level: options.logLevel)
        guard engine == nil else {
            log.warn("configure() was already called; ignoring the second call.")
            return
        }
        if !apiKey.hasPrefix("ulk_") { log.error("That doesn't look like an SDK key (they start with \"ulk_\").") }

        let dir = Storage.directory()
        let created = Engine(
            device: AppleDevice.info(sdkName: sdkName, sdkVersion: sdkVersion, debug: options.debug),
            transport: URLSessionTransport(baseURL: options.baseURL, apiKey: apiKey, userAgent: "Unolink-iOS/\(version)"),
            store: FileKeyValueStore(directory: dir),
            queueStore: FileQueueStore(directory: dir),
            scheduler: DispatchScheduler(),
            clock: SystemClock(),
            log: log,
            runOnMain: { block in DispatchQueue.main.async(execute: block) })
        engine = created
        if let handler = pendingHandler { created.setListener(handler) }
        lifecycle = Lifecycle(engine: created)
        created.start()
    }

    /// Your own event, e.g. `track("level_up", properties: ["level": 3])`. Values: strings, numbers or booleans.
    @objc(track:properties:)
    public static func track(_ name: String, properties: [String: Any]? = nil) {
        withEngine { $0.track(name, properties: properties, revenue: nil) }
    }

    /// The user finished the onboarding screens (send it before any paywall or sign-up that follows them).
    @objc(onboardingCompletedWithProperties:)
    public static func onboardingCompleted(properties: [String: Any]? = nil) {
        withEngine { $0.track("onboarding_completed", properties: properties, revenue: nil) }
    }

    /// An onboarding screen appeared. Call it when the screen shows (`.onAppear`), not from its button. `step` is a fixed
    /// screen ID such as "goal", never user data; `index` its position (0, 1, 2…); `flow` which onboarding, if you run
    /// more than one. Free: an onboarding costs one event (its `onboardingCompleted`) however many screens it has.
    public static func onboardingStep(_ step: String, index: Int? = nil, flow: String? = nil) {
        withEngine { $0.track("onboarding_step", properties: onboarding(step, index, flow), revenue: nil) }
    }

    /// The user tapped Skip on the onboarding screen `step`. Free, like `onboardingStep`.
    public static func onboardingSkipped(_ step: String, index: Int? = nil, flow: String? = nil) {
        withEngine { $0.track("onboarding_skipped", properties: onboarding(step, index, flow), revenue: nil) }
    }

    /// Objective-C: `[Unolink onboardingStep:@"goal" index:@1 flow:nil]` (`index` an NSNumber or nil).
    @available(swift, obsoleted: 1)
    @objc(onboardingStep:index:flow:)
    public static func objcOnboardingStep(_ step: String, index: NSNumber?, flow: String?) {
        onboardingStep(step, index: index?.intValue, flow: flow)
    }

    /// Objective-C: `[Unolink onboardingSkipped:@"goal" index:nil flow:nil]`.
    @available(swift, obsoleted: 1)
    @objc(onboardingSkipped:index:flow:)
    public static func objcOnboardingSkipped(_ step: String, index: NSNumber?, flow: String?) {
        onboardingSkipped(step, index: index?.intValue, flow: flow)
    }

    /// A paywall was shown. `placement` says where: "onboarding", "feature_gate", or your own name.
    @objc(paywallViewedWithPlacement:properties:)
    public static func paywallViewed(placement: String? = nil, properties: [String: Any]? = nil) {
        withEngine { $0.track("paywall_viewed", properties: with("placement", placement, properties), revenue: nil) }
    }

    /// The user closed a paywall without buying.
    @objc(paywallSkippedWithPlacement:properties:)
    public static func paywallSkipped(placement: String? = nil, properties: [String: Any]? = nil) {
        withEngine { $0.track("paywall_skipped", properties: with("placement", placement, properties), revenue: nil) }
    }

    /// An account was created (in many apps this comes after the paywall).
    @objc(signUpWithMethod:properties:)
    public static func signUp(method: String? = nil, properties: [String: Any]? = nil) {
        withEngine { $0.track("sign_up", properties: with("method", method, properties), revenue: nil) }
    }

    /// Someone signed in to an account they already had (a returning user). Not for new accounts: those are `signUp`.
    @objc(signInWithMethod:properties:)
    public static func signIn(method: String? = nil, properties: [String: Any]? = nil) {
        withEngine { $0.track("sign_in", properties: with("method", method, properties), revenue: nil) }
    }

    /// A free trial started.
    @objc(trialStartedWithProductId:properties:)
    public static func trialStarted(productId: String? = nil, properties: [String: Any]? = nil) {
        withEngine { $0.track("trial_started", properties: with("product_id", productId, properties), revenue: nil) }
    }

    /// Objective-C: `[Unolink purchaseWithAmount:[NSDecimalNumber decimalNumberWithString:@"49.99"] currency:@"USD" …]`.
    @objc(purchaseWithAmount:currency:productId:properties:)
    public static func purchase(amount: NSDecimalNumber, currency: String, productId: String?, properties: [String: Any]?) {
        purchase(amount: amount.decimalValue, currency: currency, productId: productId, properties: properties)
    }

    /// A purchase with its exact price (a `Decimal`, e.g. StoreKit's `product.price`) and ISO 4217 currency, e.g. "USD".
    public static func purchase(amount: Decimal, currency: String, productId: String? = nil, properties: [String: Any]? = nil) {
        withEngine { engine in
            guard let value = Payloads.amount(amount) else {
                ConsoleLogger(level: .error).error("purchase(): amount must be zero or more, with at most 6 decimals. Not recorded.")
                return
            }
            guard Payloads.isValidCurrency(currency) else {
                ConsoleLogger(level: .error).error("purchase(): currency must be a 3-letter ISO 4217 code such as \"USD\". Not recorded.")
                return
            }
            engine.track("purchase", properties: with("product_id", productId, properties), revenue: (value, currency))
        }
    }

    /// The user closed the App Store purchase sheet without paying.
    @objc(purchaseCancelledWithProductId:properties:)
    public static func purchaseCancelled(productId: String? = nil, properties: [String: Any]? = nil) {
        withEngine { $0.track("purchase_cancelled", properties: with("product_id", productId, properties), revenue: nil) }
    }

    /// The purchase failed (payment declined, store error). `reason` is your own short description.
    @objc(purchaseFailedWithProductId:reason:properties:)
    public static func purchaseFailed(productId: String? = nil, reason: String? = nil, properties: [String: Any]? = nil) {
        withEngine { $0.track("purchase_failed", properties: with("reason", reason, with("product_id", productId, properties)), revenue: nil) }
    }

    /// Your app's own ID for the user, e.g. the RevenueCat app user ID. Lets Unolink join server-side purchase data
    /// (renewals, cancellations, refunds) to the install. Unolink stores only a keyed hash of it. Pass nil on sign-out.
    @objc(setUserId:)
    public static func setUserId(_ userId: String?) {
        withEngine { $0.setUserId(userId) }
    }

    /// Called once per install, on the main thread, when the install was attributed to a Unolink link with certainty.
    /// On iPhone that's rare today (Apple has no install referrer, and Unolink never fingerprints); it's here so the same
    /// code works on every platform.
    @objc(onDeferredDeepLink:)
    public static func onDeferredDeepLink(_ handler: ((UnolinkDeepLink) -> Void)?) {
        lock.lock()
        pendingHandler = handler
        let e = engine
        lock.unlock()
        e?.setListener(handler)
    }

    /// The random ID of this install (nil before `configure`). It identifies no person or device.
    @objc public static var installId: String? {
        lock.lock(); defer { lock.unlock() }
        return engine?.publicInstallId
    }

    /// Sends queued events now. Normally not needed.
    @objc public static func flush() {
        withEngine { $0.flushNow() }
    }

    /// Turns tracking off (queued events are deleted) or back on. Remembered across launches.
    @objc(setEnabled:)
    public static func setEnabled(_ enabled: Bool) {
        withEngine { $0.setEnabled(enabled) }
    }

    /// The server accepts only these three on onboarding events.
    static func onboarding(_ step: String, _ index: Int?, _ flow: String?) -> [String: Any] {
        var properties: [String: Any] = ["step": step]
        if let index { properties["index"] = index }
        if let flow { properties["flow"] = flow }
        return properties
    }

    private static func with(_ key: String, _ value: String?, _ properties: [String: Any]?) -> [String: Any]? {
        guard let value = value else { return properties }
        var out = properties ?? [:]
        out[key] = value
        return out
    }

    private static func withEngine(_ block: (Engine) -> Void) {
        lock.lock()
        let e = engine
        lock.unlock()
        guard let engine = e else {
            ConsoleLogger(level: .warn).warn("Call Unolink.configure(apiKey:) at app launch first; event ignored.")
            return
        }
        block(engine)
    }
}
