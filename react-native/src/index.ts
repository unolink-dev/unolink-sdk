import { useEffect } from "react"
import type { EventSubscription } from "react-native"
import Native, { type NativeDeepLink } from "./NativeRNUnolink"
import { eventProblems, MAX_USER_ID_LENGTH, onboardingProblems, type Properties } from "./rules"
import pkg from "../package.json"

/** This package's version (sent with every install as the SDK version). */
export const VERSION: string = pkg.version

declare const __DEV__: boolean | undefined
const isDev = typeof __DEV__ !== "undefined" && __DEV__

export type LogLevel = "none" | "error" | "warn" | "info" | "debug"

export type UnolinkOptions = {
  /** The SDK API. Defaults to production; use "https://api-uat.unolink.dev" while testing. */
  baseUrl?: string
  /** How much the SDK logs (Xcode console / Logcat, tag "Unolink"). Default "warn". */
  logLevel?: LogLevel
  /**
   * Marks this install as a test device (hidden in the dashboard unless "Include test devices" is on). Defaults to
   * `__DEV__`. TestFlight, Xcode, adb and Android Studio builds are test devices on their own; pass true for builds the
   * phone can't recognise, such as Google Play testing tracks.
   */
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

export type { Properties }

/** Where a paywall was shown. Your own names work too. */
export type PaywallPlacement = "onboarding" | "launch" | "feature_gate" | "settings" | (string & {})

/** How someone signed up or in. Your own names work too. */
export type AuthMethod = "email" | "apple" | "google" | "phone" | "anonymous" | (string & {})

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

type NativeModule = NonNullable<typeof Native>

/** Before configure, calls wait here (in order) and run right after it: an app that restores its session first keeps its user ID. */
const MAX_WAITING = 200
let waiting: ((native: NativeModule) => void)[] = []
let configured = false

const warned = new Set<string>()
function warnOnce(message: string, always = false): void {
  if ((!isDev && !always) || warned.has(message)) return
  warned.add(message)
  console.warn(`[Unolink] ${message}`)
}

/** Runs a native call now, or once configure has run. Never throws: analytics must never break the app. */
function call(run: (native: NativeModule) => void): void {
  if (!Native) {
    warnOnce("The native module isn't in this build (Expo Go, Jest, web, or an update to a build without the SDK): calls do nothing.")
    return
  }
  if (!configured) {
    warnOnce("A call came before Unolink.configure(): it waits and is sent once configure runs. Configure as early as possible.")
    if (waiting.length < MAX_WAITING) waiting.push(run)
    else warnOnce(`More than ${MAX_WAITING} calls before configure: the rest are dropped.`, true)
    return
  }
  try {
    run(Native)
  } catch (e) {
    warnOnce(`A call failed: ${String(e)}`, true)
  }
}

function track(name: string, properties: Properties | null): void {
  if (isDev) for (const problem of eventProblems(name, properties)) warnOnce(`${problem} The server will reject or trim it.`)
  call((n) => n.track(name, properties))
}

// Deferred deep links. The native SDK delivers the link once, as soon as it's known (on Android that can be before
// your screens subscribe), so it's kept here: a link that arrives with no listener goes to the first one added, and
// getPendingDeferredDeepLink() returns it until consumeDeferredDeepLink().
type DeepLinkListener = (link: UnolinkDeepLink) => void
const deepLinkListeners = new Set<DeepLinkListener>()
let undelivered: UnolinkDeepLink | null = null
let pending: UnolinkDeepLink | null = null

function receive(native: NativeDeepLink): void {
  const link = native as UnolinkDeepLink
  pending = link
  if (deepLinkListeners.size === 0) {
    undelivered = link
    return
  }
  for (const listener of [...deepLinkListeners]) deliver(listener, link)
}

function deliver(listener: DeepLinkListener, link: UnolinkDeepLink): void {
  try {
    listener(link)
  } catch (e) {
    warnOnce(`A deferred deep link listener threw: ${String(e)}`, true)
  }
}

/**
 * Unolink: which link or ad brings installs, onboarding, paywall views, trials and purchases. Calls never throw and
 * never block: events are queued on the device and sent in the background by the native iOS/Android SDK.
 */
export const Unolink = {
  /**
   * Call once, as early as possible (e.g. in your root layout). The key is your app's SDK key (fine to ship in the app).
   * Calls made before this wait and are sent right after it.
   */
  configure(apiKey: string, options: UnolinkOptions = {}): void {
    if (!Native) {
      call(() => {})
      return
    }
    if (configured) {
      warnOnce("Unolink.configure() was called again; only the first call counts.")
      return
    }
    if (typeof apiKey !== "string" || !apiKey.trim().startsWith("ulk_")) {
      warnOnce(`Unolink.configure() needs your app's SDK key (it starts with "ulk_"); got ${apiKey ? "something else" : "nothing"} `
        + "(is it missing from .env?). Nothing is recorded.", true)
      return
    }
    try {
      // Subscribed before the native SDK starts, so no deferred link can arrive unheard.
      Native.onDeferredDeepLink(receive)
      Native.configure(apiKey.trim(), options.baseUrl ?? null, options.logLevel ?? "warn", options.debug ?? isDev, VERSION)
    } catch (e) {
      warnOnce(`Unolink.configure() failed: ${String(e)}`, true)
      return
    }
    configured = true
    const queued = waiting
    waiting = []
    for (const run of queued) call(run)
  },

  /** Whether configure has run with a key and the native SDK is in this build. */
  isConfigured(): boolean {
    return configured
  },

  /** Your own event, e.g. track("level_up", { level: 3 }). */
  track(name: string, properties?: Properties): void {
    track(name, properties ?? null)
  },

  /** The user finished the onboarding screens (send it before any paywall or sign-up that follows them). Counted once per install. */
  onboardingCompleted(properties?: Properties): void {
    track("onboarding_completed", properties ?? null)
  },

  /**
   * An onboarding screen appeared. Call it when the screen shows (or use `useOnboardingStep`), not from its button.
   * `step` is a fixed screen ID such as "goal", never user data. Free: an onboarding costs one event (its
   * `onboardingCompleted`) however many screens it has.
   */
  onboardingStep(step: string, screen?: OnboardingScreen): void {
    trackOnboarding("onboarding_step", onboarding(step, screen))
  },

  /** The user tapped Skip on the onboarding screen `step`. Free, like `onboardingStep`. */
  onboardingSkipped(step: string, screen?: OnboardingScreen): void {
    trackOnboarding("onboarding_skipped", onboarding(step, screen))
  },

  /**
   * A paywall was shown: every time it appears (each counts toward your quota; funnels count each person once).
   * Don't send it to subscribers who never see one. placement: "onboarding", "launch", "feature_gate", or your own name.
   */
  paywallViewed(placement?: PaywallPlacement, properties?: Properties): void {
    track("paywall_viewed", withValue("placement", placement, properties))
  },

  /** The user closed a paywall without buying (a close button, swipe-down or back). Not for a purchase still waiting on approval. */
  paywallSkipped(placement?: PaywallPlacement, properties?: Properties): void {
    track("paywall_skipped", withValue("placement", placement, properties))
  },

  /** A new account was created. */
  signUp(method?: AuthMethod, properties?: Properties): void {
    track("sign_up", withValue("method", method, properties))
  },

  /** Someone signed in to an account they already had (a returning user). Not for new accounts: those are `signUp`. */
  signIn(method?: AuthMethod, properties?: Properties): void {
    track("sign_in", withValue("method", method, properties))
  },

  /** The user chose to continue without an account (guest mode) on a sign-up screen. Not a drop-off. */
  signUpSkipped(properties?: Properties): void {
    track("sign_up_skipped", properties ?? null)
  },

  /** A free trial started. Not needed when RevenueCat is connected to Unolink (it reports trials itself). */
  trialStarted(productId?: string, properties?: Properties): void {
    track("trial_started", withValue("product_id", productId, properties))
  },

  /**
   * A purchase with its price, e.g. purchase("49.99", "USD", "pro_yearly"). Prefer a string amount so it's never
   * rounded. Not needed when RevenueCat is connected to Unolink (it reports purchases, renewals and refunds itself).
   */
  purchase(amount: string | number, currency: string, productId?: string, properties?: Properties): void {
    if (isDev) for (const problem of eventProblems("purchase", properties ?? null)) warnOnce(`${problem} The server will reject or trim it.`)
    call((n) => n.purchase(String(amount), currency, productId ?? null, properties ?? null))
  },

  /** The user closed the store's purchase sheet without paying. */
  purchaseCancelled(productId?: string, properties?: Properties): void {
    track("purchase_cancelled", withValue("product_id", productId, properties))
  },

  /** The purchase failed. reason is your own short description. */
  purchaseFailed(productId?: string, reason?: string, properties?: Properties): void {
    track("purchase_failed", withValue("reason", reason, withValue("product_id", productId, properties) ?? undefined))
  },

  /**
   * Your app's user ID, e.g. the ID you pass to RevenueCat's Purchases.logIn, so RevenueCat purchases join this install.
   * Unolink stores only a keyed hash of it. Pass null on sign-out.
   */
  setUserId(userId: string | null): void {
    if (userId != null && userId.trim().length > MAX_USER_ID_LENGTH)
      warnOnce(`setUserId: the ID is over ${MAX_USER_ID_LENGTH} characters and is ignored.`, true)
    call((n) => n.setUserId(userId))
  },

  /** The random ID of this install (null before configure, or without the native module). It identifies no person or device. */
  getInstallId(): string | null {
    if (!Native || !configured) return null
    try {
      return Native.getInstallId()
    } catch {
      return null
    }
  },

  /** Sends queued events now. Normally not needed. */
  flush(): void {
    call((n) => n.flush())
  },

  /** Turns tracking off (queued events are deleted) or back on. Remembered across launches. */
  setEnabled(enabled: boolean): void {
    call((n) => n.setEnabled(enabled))
  },

  /**
   * Called once per install when it came from a Unolink link. A link that arrived before any listener goes to the first
   * one you add. If its screen sits behind onboarding or sign-in, use getPendingDeferredDeepLink() once that's done instead.
   */
  addDeferredDeepLinkListener(listener: DeepLinkListener): EventSubscription {
    deepLinkListeners.add(listener)
    if (undelivered) {
      const link = undelivered
      undelivered = null
      deliver(listener, link)
    }
    return { remove: () => void deepLinkListeners.delete(listener) } as EventSubscription
  },

  /**
   * The deferred deep link of this launch that hasn't been consumed yet, or null. For links whose screen sits behind
   * onboarding or sign-in: when that's done, open it and call consumeDeferredDeepLink(). Kept for this launch only.
   */
  getPendingDeferredDeepLink(): UnolinkDeepLink | null {
    return pending
  },

  /** Marks the pending deferred deep link as handled: getPendingDeferredDeepLink() returns null from now on. */
  consumeDeferredDeepLink(): void {
    pending = null
    undelivered = null
  },
}

function trackOnboarding(name: string, properties: Properties): void {
  if (isDev) for (const problem of onboardingProblems(name, properties)) warnOnce(`${problem} The server will reject this event.`)
  track(name, properties)
}

/**
 * Sends `onboardingStep` when the screen mounts: `useOnboardingStep("goal", { index: 0 })`. In development, React's
 * StrictMode mounts twice and so sends it twice; production builds send it once.
 */
export function useOnboardingStep(step: string, screen?: OnboardingScreen): void {
  const index = screen?.index
  const flow = screen?.flow
  useEffect(() => {
    Unolink.onboardingStep(step, { index, flow })
  }, [step, index, flow])
}

export default Unolink
