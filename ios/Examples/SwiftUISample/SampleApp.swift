import SwiftUI
import Unolink

@main
struct SampleApp: App {
    @StateObject private var state = SampleState()

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "UnolinkKey") as? String ?? ""
        // The sample always talks to UAT and marks itself as a test device.
        Unolink.configure(apiKey: key, options: UnolinkOptions(baseURL: "https://api-uat.unolink.dev", logLevel: .debug, debug: true))
        // Automated end-to-end runs: `-unolinkAutoRun` fires every button's event once, then flushes.
        if ProcessInfo.processInfo.arguments.contains("-unolinkAutoRun") { SampleApp.fireAll() }
    }

    static func fireAll() {
        Unolink.onboardingCompleted(properties: ["steps": 4])
        Unolink.paywallViewed(placement: "onboarding")
        Unolink.paywallSkipped(placement: "onboarding")
        Unolink.setUserId("ios-sample-user")
        Unolink.signUp(method: "apple")
        Unolink.trialStarted(productId: "pro_yearly")
        Unolink.purchase(amount: Decimal(string: "4.99")!, currency: "USD", productId: "pro_monthly")
        Unolink.purchaseCancelled(productId: "pro_monthly")
        Unolink.track("level_up", properties: ["level": 3])
        Unolink.flush()
    }

    var body: some Scene {
        WindowGroup { ContentView().environmentObject(state) }
    }
}

final class SampleState: ObservableObject {
    @Published var note = ""
    @Published var deepLink: String?

    init() {
        Unolink.onDeferredDeepLink { [weak self] link in
            self?.deepLink = "\(link.deepLink ?? "-") \(link.params) via /\(link.linkSlug ?? "")"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var state: SampleState
    private let key = Bundle.main.object(forInfoDictionaryKey: "UnolinkKey") as? String ?? ""

    var body: some View {
        NavigationView {
            List {
                Section("This install") {
                    Text("API: api-uat.unolink.dev")
                    Text("Key: \(key.isEmpty ? "missing: add Secrets.xcconfig" : String(key.prefix(12)) + "…")")
                    Text("Install ID: \(Unolink.installId ?? "…")").font(.footnote.monospaced())
                    Text("Deferred deep link: \(state.deepLink ?? "none (expected on iPhone)")")
                    if !state.note.isEmpty { Text(state.note).foregroundColor(.secondary) }
                }
                Section("Events") {
                    button("Onboarding completed") { Unolink.onboardingCompleted(properties: ["steps": 4]) }
                    button("Paywall viewed (onboarding)") { Unolink.paywallViewed(placement: "onboarding") }
                    button("Paywall skipped") { Unolink.paywallSkipped(placement: "onboarding") }
                    button("Sign up (set user ID)") { Unolink.setUserId("ios-sample-user"); Unolink.signUp(method: "apple") }
                    button("Trial started") { Unolink.trialStarted(productId: "pro_yearly") }
                    button("Purchase 4.99 USD") { Unolink.purchase(amount: Decimal(string: "4.99")!, currency: "USD", productId: "pro_monthly") }
                    button("Purchase cancelled") { Unolink.purchaseCancelled(productId: "pro_monthly") }
                    button("Custom event: level_up") { Unolink.track("level_up", properties: ["level": 3]) }
                    button("Send now (flush)") { Unolink.flush() }
                }
            }
            .navigationTitle("Unolink sample")
        }
    }

    private func button(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title) {
            action()
            state.note = "Sent: \(title)"
        }
    }
}
