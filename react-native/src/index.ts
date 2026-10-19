import { useEffect } from "react"
import type { EventSubscription } from "react-native"
import Native from "./NativeRNUnolink"

/** This package's version (sent with every install as the SDK version). */
export const VERSION = "0.2.1"

export type LogLevel = "none" | "error" | "warn" | "info" | "debug"

export type UnolinkOptions = {
  /** The SDK API. Defaults to production; use "https://api-uat.unolink.dev" while testing. */
  baseUrl?: string
  /** How much the SDK logs (Xcode console / Logcat, tag "Unolink"). Default "warn". */
  logLevel?: LogLevel
  /** Marks this install as a test device (hidden in the dashboard unless "Include test devices" is on). Pass `__DEV__`. */
  debug?: boolean
}

/** Where to take someone who just installed from a Unolink link (Android; iPhone only when attributed with certainty). */
export type UnolinkDeepLink = {
  /** The link's deep link, e.g. "/promo/3for2", or null. */
  deepLink: string | null
  /** The link's parameters. */
  params: Record<string, string>
  /** The campaign link's path (e.g. "tiktok"), or null for the app's main link. */
  linkSlug: string | null
  clickId: string
}

export type Properties = Record<string, string | number | boolean>

/** Where an onboarding screen sits: its position (0, 1, 2…) and which onboarding it belongs to, if you run more than one. */
export type OnboardingScreen = { index?: number; flow?: string }

/** The server accepts only step, index and flow on onboarding events. */
function onboarding(step: string, screen?: OnboardingScreen): Properties {
  const properties: Properties = { step }
  if (screen?.index != null) properties.index = screen.index
  if (screen?.flow != null) properties.flow = screen.flow
  return properties
}

function withValue(key: string, value: string | undefined | null, properties?: Properties): Properties | null {
  if (value == null) return properties ?? null
  return { ...properties, [key]: value }
}

/**
 * Unolink: which link or ad brings installs, onboarding, paywall views, trials and purchases. Calls never throw and
 * never block: events are queued on the device and sent in the background by the native iOS/Android SDK.
 */
export const Unolink = {
  /** Call once, as early as possible (e.g. in your root layout). The key is your app's SDK key (fine to ship in the app). */
  configure(apiKey: string, options: UnolinkOptions = {}): void {
    Native.configure(apiKey, options.baseUrl ?? null, options.logLevel ?? "warn", options.debug ?? false, VERSION)
  },

  /** Your own event, e.g. track("level_up", { level: 3 }). */
  track(name: string, properties?: Properties): void {
    Native.track(name, properties ?? null)
  },

  /** The user finished the onboarding screens (send it before any paywall or sign-up that follows them). */
  onboardingCompleted(properties?: Properties): void {
    Native.track("onboarding_completed", properties ?? null)
  },

  /**
   * An onboarding screen appeared. Call it when the screen shows (or use `useOnboardingStep`), not from its button.
   * `step` is a fixed screen ID such as "goal", never user data. Free: an onboarding costs one event (its
   * `onboardingCompleted`) however many screens it has.
   */
  onboardingStep(step: string, screen?: OnboardingScreen): void {
    Native.track("onboarding_step", onboarding(step, screen))
  },

  /** The user tapped Skip on the onboarding screen `step`. Free, like `onboardingStep`. */
  onboardingSkipped(step: string, screen?: OnboardingScreen): void {
    Native.track("onboarding_skipped", onboarding(step, screen))
  },

  /** A paywall was shown. placement: "onboarding", "feature_gate", or your own name. */
  paywallViewed(placement?: string, properties?: Properties): void {
    Native.track("paywall_viewed", withValue("placement", placement, properties))
  },

  /** The user closed a paywall without buying. */
  paywallSkipped(placement?: string, properties?: Properties): void {
    Native.track("paywall_skipped", withValue("placement", placement, properties))
  },

  /** An account was created. */
  signUp(method?: string, properties?: Properties): void {
    Native.track("sign_up", withValue("method", method, properties))
  },

  /** A free trial started. Not needed when RevenueCat is connected to Unolink (it reports trials itself). */
  trialStarted(productId?: string, properties?: Properties): void {
    Native.track("trial_started", withValue("product_id", productId, properties))
  },

  /**
   * A purchase with its price, e.g. purchase("49.99", "USD", "pro_yearly"). Prefer a string amount so it's never
   * rounded. Not needed when RevenueCat is connected to Unolink (it reports purchases, renewals and refunds itself).
   */
  purchase(amount: string | number, currency: string, productId?: string, properties?: Properties): void {
    Native.purchase(String(amount), currency, productId ?? null, properties ?? null)
  },

  /** The user closed the store's purchase sheet without paying. */
  purchaseCancelled(productId?: string, properties?: Properties): void {
    Native.track("purchase_cancelled", withValue("product_id", productId, properties))
  },

  /** The purchase failed. reason is your own short description. */
  purchaseFailed(productId?: string, reason?: string, properties?: Properties): void {
    Native.track("purchase_failed", withValue("reason", reason, withValue("product_id", productId, properties) ?? undefined))
  },

  /**
   * Your app's user ID, e.g. the ID you pass to RevenueCat's Purchases.logIn, so RevenueCat purchases join this install.
   * Unolink stores only a keyed hash of it. Pass null on sign-out.
   */
  setUserId(userId: string | null): void {
    Native.setUserId(userId)
  },

  /** The random ID of this install (null before configure). It identifies no person or device. */
  getInstallId(): string | null {
    return Native.getInstallId()
  },

  /** Sends queued events now. Normally not needed. */
  flush(): void {
    Native.flush()
  },

  /** Turns tracking off (queued events are deleted) or back on. Remembered across launches. */
  setEnabled(enabled: boolean): void {
    Native.setEnabled(enabled)
  },

  /** Called once per install when it came from a Unolink link: open link.deepLink. Delivered even if added late. */
  addDeferredDeepLinkListener(listener: (link: UnolinkDeepLink) => void): EventSubscription {
    return Native.onDeferredDeepLink((link) => listener(link as UnolinkDeepLink))
  },
}

/** Sends `onboardingStep` when the screen mounts: `useOnboardingStep("goal", { index: 0 })`. */
export function useOnboardingStep(step: string, screen?: OnboardingScreen): void {
  const index = screen?.index
  const flow = screen?.flow
  useEffect(() => {
    Unolink.onboardingStep(step, { index, flow })
  }, [step, index, flow])
}

export default Unolink
