// An official Jest mock for apps that use @unolink/react-native:
//
//   jest.mock("@unolink/react-native", () => require("@unolink/react-native/jest"))
//
// Every call is a jest.fn (so expect(Unolink.signUp).toHaveBeenCalledWith("apple") works), nothing touches native code,
// and Unolink.__calls lists every call in order: [["signUp", "apple"], ...]. Unolink.__reset() clears both between tests.
// Deferred deep links: Unolink.__emitDeferredDeepLink(link) delivers one as the native SDK would.
"use strict"

const calls = []
const listeners = new Set()
let configured = false
let pending = null
let undelivered = null

const fn = (name, impl = () => undefined) => {
  const run = (...args) => {
    calls.push([name, ...args])
    return impl(...args)
  }
  return typeof jest !== "undefined" ? jest.fn(run) : run
}

const Unolink = {
  configure: fn("configure", () => {
    configured = true
  }),
  isConfigured: fn("isConfigured", () => configured),
  track: fn("track"),
  onboardingCompleted: fn("onboardingCompleted"),
  onboardingStep: fn("onboardingStep"),
  onboardingSkipped: fn("onboardingSkipped"),
  paywallViewed: fn("paywallViewed"),
  paywallSkipped: fn("paywallSkipped"),
  signUp: fn("signUp"),
  signIn: fn("signIn"),
  signUpSkipped: fn("signUpSkipped"),
  trialStarted: fn("trialStarted"),
  purchase: fn("purchase"),
  purchaseCancelled: fn("purchaseCancelled"),
  purchaseFailed: fn("purchaseFailed"),
  setUserId: fn("setUserId"),
  getInstallId: fn("getInstallId", () => (configured ? "00000000-0000-4000-8000-000000000000" : null)),
  flush: fn("flush"),
  setEnabled: fn("setEnabled"),
  addDeferredDeepLinkListener: fn("addDeferredDeepLinkListener", (listener) => {
    listeners.add(listener)
    if (undelivered) {
      const link = undelivered
      undelivered = null
      listener(link)
    }
    return { remove: () => listeners.delete(listener) }
  }),
  getPendingDeferredDeepLink: fn("getPendingDeferredDeepLink", () => pending),
  consumeDeferredDeepLink: fn("consumeDeferredDeepLink", () => {
    pending = null
    undelivered = null
  }),

  __calls: calls,
  __emitDeferredDeepLink(link) {
    pending = link
    if (listeners.size === 0) undelivered = link
    else for (const listener of [...listeners]) listener(link)
  },
  __reset() {
    calls.length = 0
    listeners.clear()
    configured = false
    pending = null
    undelivered = null
    for (const value of Object.values(Unolink)) if (value && typeof value.mockClear === "function") value.mockClear()
  },
}

function useOnboardingStep(step, screen) {
  calls.push(["useOnboardingStep", step, screen])
}

module.exports = { __esModule: true, Unolink, default: Unolink, useOnboardingStep, VERSION: require("./package.json").version }
