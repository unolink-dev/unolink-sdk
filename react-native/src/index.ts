import { useEffect } from "react"
import { AppState, type EventSubscription } from "react-native"
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

/** The answers `heardFrom` takes ("Where did you hear about us?"). Map your own onboarding options to these. */
export const HEARD_FROM_SOURCES = ["app_store", "google_play", "search", "tiktok", "instagram", "facebook", "youtube", "x", "reddit", "friend", "ad", "podcast", "blog", "other"] as const
export type HeardFromSource = (typeof HEARD_FROM_SOURCES)[number]

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

/**
 * The parts of react-native-purchases' `Purchases` that `connectRevenueCat` uses. Pass `Purchases` itself: Unolink
 * doesn't depend on RevenueCat, so apps without it don't install it.
 */
export type RevenueCatPurchases = {
  getAppUserID(): Promise<string>
  addCustomerInfoUpdateListener?(listener: (customerInfo: unknown) => void): void
  removeCustomerInfoUpdateListener?(listener: (customerInfo: unknown) => void): unknown
}

type RevenueCatLink = { check(): Promise<void>; disconnect(): void }
let revenueCat: RevenueCatLink | null = null

function linkRevenueCat(purchases: RevenueCatPurchases): RevenueCatLink {
  let reported: string | null = null
  let reads = 0
  let disconnected = false
  let appState: { remove(): void } | null = null

  async function check(): Promise<void> {
    if (disconnected) return
    const read = ++reads
    let id: string | null | undefined
    try {
      id = await purchases.getAppUserID()
    } catch {
      return // RevenueCat isn't configured yet: read again on the next update or when the app comes back.
    }
    // A newer read wins: answers can come back out of order.
    if (disconnected || read !== reads || typeof id !== "string") return
    id = id.trim()
    if (!id || id.length > MAX_USER_ID_LENGTH || id === reported) return
    reported = id
    Unolink.setUserId(id)
  }

  const onCustomerInfo = () => void check()
  try {
    purchases.addCustomerInfoUpdateListener?.(onCustomerInfo)
  } catch (e) {
    warnOnce(`connectRevenueCat: couldn't listen for customer info updates: ${String(e)}`, true)
  }
  try {
    appState = AppState.addEventListener("change", (state) => {
      if (state === "active") void check()
    })
  } catch {
    appState = null
  }

  return {
    check,
    disconnect() {
      if (disconnected) return
      disconnected = true
      try {
        purchases.removeCustomerInfoUpdateListener?.(onCustomerInfo)
      } catch {}
      appState?.remove()
      appState = null
    },
  }
}

// Deferred deep links. The native SDK delivers the link to listeners once per install, as soon as it's known (on Android
// that can be before your screens subscribe), so it's kept here: a link that arrives with no listener goes to the first
// one added. getPendingDeferredDeepLink() returns it until consumeDeferredDeepLink(): on Android the native SDK keeps
// it on disk, so it survives app restarts (30 days at most); a link delivered this launch is also kept in memory here.
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

  /**
   * "Where did you hear about us?": the user's answer from your onboarding, as one of HEARD_FROM_SOURCES (anything else
   * is stored as "other"). Free, and the latest answer counts. Never send what the user typed.
   */
  heardFrom(source: HeardFromSource): void {
    track("heard_from", { source })
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
   * Your app's user ID: RevenueCat's app user ID (`await Purchases.getAppUserID()`, also while it's anonymous) if you
   * use RevenueCat, or let connectRevenueCat do it, so RevenueCat purchases join this install. Unolink stores only a
   * keyed hash of it. Pass null on sign-out.
   */
  setUserId(userId: string | null): void {
    if (userId != null && userId.trim().length > MAX_USER_ID_LENGTH)
      warnOnce(`setUserId: the ID is over ${MAX_USER_ID_LENGTH} characters and is ignored.`, true)
    call((n) => n.setUserId(userId))
  },

  /**
   * Keeps the user ID equal to RevenueCat's app user ID, so RevenueCat purchases (a guest's too) join this install:
   * `Unolink.connectRevenueCat(Purchases)` with react-native-purchases' `Purchases`. Reads `Purchases.getAppUserID()`
   * now, on every customer info update (purchases, logIn, logOut) and whenever the app comes back to the foreground,
   * and reports it only when it changed. Errors (RevenueCat not configured yet) are ignored and it's read again later.
   * Call it once, before or after configure. Returns a function that disconnects. Use this or setUserId, not both.
   */
  connectRevenueCat(purchases: RevenueCatPurchases): () => void {
    revenueCat?.disconnect()
    if (!purchases || typeof purchases.getAppUserID !== "function") {
      warnOnce("connectRevenueCat needs react-native-purchases' Purchases (it has getAppUserID).", true)
      return () => {}
    }
    const link = linkRevenueCat(purchases)
    revenueCat = link
    void link.check()
    return () => {
      link.disconnect()
      if (revenueCat === link) revenueCat = null
    }
  },

  /**
   * Reads RevenueCat's app user ID now and reports it if it changed. Normally not needed: connectRevenueCat already
   * listens for customer info updates. Does nothing without it.
   */
  async revenueCatUserChanged(): Promise<void> {
    await revenueCat?.check()
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
   * Called once per install when it came from a Unolink link: open it, then call consumeDeferredDeepLink(). A link that
   * arrived before any listener goes to the first one you add. Listeners aren't called again on later launches, so if
   * its screen sits behind onboarding or sign-in, use getPendingDeferredDeepLink() once that's done instead.
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
   * The deferred deep link that hasn't been consumed yet, or null. For links whose screen sits behind onboarding or
   * sign-in: when that's done, open it and call consumeDeferredDeepLink(). Android keeps it on the device across app
   * restarts (a new user who quits mid-onboarding still gets it next time) until it's consumed, for at most 30 days
   * after the install, whether or not a listener already received it. Null before configure() and until Google Play
   * has answered (the listener tells you when it's known).
   */
  getPendingDeferredDeepLink(): UnolinkDeepLink | null {
    if (Native && configured && typeof Native.getPendingDeferredDeepLink === "function") {
      try {
        const kept = Native.getPendingDeferredDeepLink()
        if (kept) return kept as UnolinkDeepLink
      } catch {}
    }
    return pending
  },

  /**
   * Marks the deferred deep link as opened: getPendingDeferredDeepLink() returns null from now on, on later launches
   * too. Call it once you've opened the link, or it's offered again on every launch for 30 days.
   */
  consumeDeferredDeepLink(): void {
    pending = null
    undelivered = null
    call((n) => {
      if (typeof n.consumeDeferredDeepLink === "function") n.consumeDeferredDeepLink()
    })
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
