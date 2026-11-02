// The JS layer's own behaviour: no native module, calls before configure, a bad key, deferred deep links, dev checks.
type Native = Record<string, jest.Mock>

/** React Native's AppState, driven by the tests. */
const appState = {
  listeners: new Set<(state: string) => void>(),
  addEventListener(_: string, listener: (state: string) => void) {
    appState.listeners.add(listener)
    return { remove: () => void appState.listeners.delete(listener) }
  },
  emit(state: string) {
    for (const listener of [...appState.listeners]) listener(state)
  },
}

/** A fresh copy of the package over a fake native module (or none), with its own state. */
function load(native: Native | null, dev = false) {
  jest.resetModules()
  appState.listeners.clear()
  ;(globalThis as { __DEV__?: boolean }).__DEV__ = dev
  jest.doMock("../src/NativeRNUnolink", () => ({ __esModule: true, default: native }))
  jest.doMock("react-native", () => ({ AppState: appState }))
  return require("../src") as typeof import("../src")
}

function fakeNative() {
  let emit: ((link: unknown) => void) | undefined
  const native: Native = {
    configure: jest.fn(),
    track: jest.fn(),
    purchase: jest.fn(),
    setUserId: jest.fn(),
    flush: jest.fn(),
    setEnabled: jest.fn(),
    getInstallId: jest.fn(() => "install-1"),
    onDeferredDeepLink: jest.fn((cb: (link: unknown) => void) => {
      emit = cb
      return { remove() {} }
    }),
  }
  return { native, emit: (link: unknown) => emit!(link) }
}

const link = { deepLink: "/promo", params: { a: "1" }, linkSlug: "tiktok", clickId: "c1" }
let warn: jest.SpyInstance

beforeEach(() => {
  warn = jest.spyOn(console, "warn").mockImplementation(() => {})
})
afterEach(() => warn.mockRestore())

test("without the native module, importing and calling never throws", () => {
  const { Unolink } = load(null)
  expect(() => {
    Unolink.configure("ulk_x")
    Unolink.track("x")
    Unolink.setUserId("u1")
    Unolink.addDeferredDeepLinkListener(() => {}).remove()
  }).not.toThrow()
  expect(Unolink.isConfigured()).toBe(false)
  expect(Unolink.getInstallId()).toBeNull()
})

test("calls before configure wait and are sent, in order, right after it", () => {
  const { native } = fakeNative()
  const { Unolink } = load(native)
  Unolink.setUserId("guest-1")
  Unolink.onboardingStep("goal", { index: 0 })
  expect(native.setUserId).not.toHaveBeenCalled()
  expect(Unolink.isConfigured()).toBe(false)

  Unolink.configure("ulk_key")
  expect(Unolink.isConfigured()).toBe(true)
  expect(native.setUserId).toHaveBeenCalledWith("guest-1")
  expect(native.track).toHaveBeenCalledWith("onboarding_step", { step: "goal", index: 0 })
  expect(native.setUserId.mock.invocationCallOrder[0]).toBeLessThan(native.track.mock.invocationCallOrder[0])
})

test("a missing key says so and doesn't start the SDK", () => {
  const error = jest.spyOn(console, "warn")
  const { native } = fakeNative()
  const { Unolink } = load(native)
  Unolink.configure(undefined as unknown as string)
  expect(native.configure).not.toHaveBeenCalled()
  expect(Unolink.isConfigured()).toBe(false)
  expect(error.mock.calls.some(([m]) => String(m).includes("ulk_"))).toBe(true)
})

test("debug defaults to __DEV__", () => {
  const dev = fakeNative()
  load(dev.native, true).Unolink.configure("ulk_key")
  expect(dev.native.configure.mock.calls[0][3]).toBe(true)
  const release = fakeNative()
  load(release.native, false).Unolink.configure("ulk_key", {})
  expect(release.native.configure.mock.calls[0][3]).toBe(false)
  const explicit = fakeNative()
  load(explicit.native, true).Unolink.configure("ulk_key", { debug: false })
  expect(explicit.native.configure.mock.calls[0][3]).toBe(false)
})

test("a deferred link that arrives before any listener goes to the first one added, once", () => {
  const { native, emit } = fakeNative()
  const { Unolink } = load(native)
  Unolink.configure("ulk_key")
  emit(link)
  const first = jest.fn()
  const second = jest.fn()
  Unolink.addDeferredDeepLinkListener(first)
  Unolink.addDeferredDeepLinkListener(second)
  expect(first).toHaveBeenCalledWith(link)
  expect(second).not.toHaveBeenCalled()
})

test("listeners added before the link get it when it arrives", () => {
  const { native, emit } = fakeNative()
  const { Unolink } = load(native)
  const listener = jest.fn()
  Unolink.addDeferredDeepLinkListener(listener)
  Unolink.configure("ulk_key")
  emit(link)
  expect(listener).toHaveBeenCalledTimes(1)
})

test("the pending link waits until it's consumed (open it after onboarding)", () => {
  const { native, emit } = fakeNative()
  const { Unolink } = load(native)
  Unolink.configure("ulk_key")
  expect(Unolink.getPendingDeferredDeepLink()).toBeNull()
  emit(link)
  expect(Unolink.getPendingDeferredDeepLink()).toEqual(link)
  Unolink.consumeDeferredDeepLink()
  expect(Unolink.getPendingDeferredDeepLink()).toBeNull()
  const late = jest.fn()
  Unolink.addDeferredDeepLinkListener(late)
  expect(late).not.toHaveBeenCalled()
})

test("in development, IDs and properties the server would reject are flagged", () => {
  const { native } = fakeNative()
  const { Unolink } = load(native, true)
  Unolink.configure("ulk_key")
  Unolink.onboardingStep("how-heard")
  Unolink.track("level", { note: "x".repeat(201) })
  const messages = warn.mock.calls.map(([m]) => String(m))
  expect(messages.some((m) => m.includes('"how-heard"'))).toBe(true)
  expect(messages.some((m) => m.includes("201 characters"))).toBe(true)
  expect(native.track).toHaveBeenCalledTimes(2) // still sent: the server decides
})

test("signUpSkipped is its own event", () => {
  const { native } = fakeNative()
  const { Unolink } = load(native)
  Unolink.configure("ulk_key")
  Unolink.signUpSkipped()
  expect(native.track).toHaveBeenCalledWith("sign_up_skipped", null)
})

test("VERSION is the package's version", () => {
  const { VERSION } = load(fakeNative().native)
  expect(VERSION).toBe(require("../package.json").version)
})

/** react-native-purchases' Purchases, as far as connectRevenueCat uses it. */
function fakePurchases(initial: string | Error) {
  let current: string | Error = initial
  const listeners = new Set<(info: unknown) => void>()
  const purchases = {
    getAppUserID: jest.fn(async () => {
      if (current instanceof Error) throw current
      return current
    }),
    addCustomerInfoUpdateListener: jest.fn((l: (info: unknown) => void) => void listeners.add(l)),
    removeCustomerInfoUpdateListener: jest.fn((l: (info: unknown) => void) => listeners.delete(l)),
  }
  return {
    purchases,
    listeners,
    set(id: string | Error) {
      current = id
    },
    emit() {
      for (const l of [...listeners]) l({ originalAppUserId: "x" })
    },
  }
}

const settle = () => new Promise((resolve) => setImmediate(resolve))

test("connectRevenueCat reports RevenueCat's ID, then only changes, on customer info updates", async () => {
  const { native } = fakeNative()
  const { Unolink } = load(native)
  Unolink.configure("ulk_key")
  const rc = fakePurchases("$RCAnonymousID:guest")
  const disconnect = Unolink.connectRevenueCat(rc.purchases)
  await settle()
  expect(native.setUserId.mock.calls).toEqual([["$RCAnonymousID:guest"]])

  rc.emit() // same ID
  await settle()
  expect(native.setUserId).toHaveBeenCalledTimes(1)

  rc.set("account-42") // Purchases.logIn
  rc.emit()
  await settle()
  expect(native.setUserId.mock.calls).toEqual([["$RCAnonymousID:guest"], ["account-42"]])

  disconnect()
  expect(rc.listeners.size).toBe(0)
  expect(appState.listeners.size).toBe(0)
  rc.set("account-7")
  rc.emit()
  await settle()
  expect(native.setUserId).toHaveBeenCalledTimes(2)
})

test("connectRevenueCat before configure: the ID waits and is sent right after it", async () => {
  const { native } = fakeNative()
  const { Unolink } = load(native)
  Unolink.connectRevenueCat(fakePurchases("$RCAnonymousID:guest").purchases)
  await settle()
  expect(native.setUserId).not.toHaveBeenCalled()
  Unolink.configure("ulk_key")
  expect(native.setUserId).toHaveBeenCalledWith("$RCAnonymousID:guest")
})

test("connectRevenueCat: errors are swallowed and the ID is read again when the app comes back", async () => {
  const { native } = fakeNative()
  const { Unolink } = load(native)
  Unolink.configure("ulk_key")
  const rc = fakePurchases(new Error("There is no singleton instance"))
  Unolink.connectRevenueCat(rc.purchases)
  await settle()
  expect(native.setUserId).not.toHaveBeenCalled()

  rc.set("$RCAnonymousID:after-logout")
  appState.emit("background")
  await settle()
  expect(native.setUserId).not.toHaveBeenCalled()
  appState.emit("active")
  await settle()
  expect(native.setUserId).toHaveBeenCalledWith("$RCAnonymousID:after-logout")
})

test("connectRevenueCat: a newer read wins when answers come back out of order", async () => {
  const { native } = fakeNative()
  const { Unolink } = load(native)
  Unolink.configure("ulk_key")
  const answers: ((id: string) => void)[] = []
  const purchases = { getAppUserID: () => new Promise<string>((resolve) => answers.push(resolve)) }
  Unolink.connectRevenueCat(purchases)
  void Unolink.revenueCatUserChanged()
  answers[1]("account-42")
  await settle()
  answers[0]("$RCAnonymousID:stale")
  await settle()
  expect(native.setUserId.mock.calls).toEqual([["account-42"]])
})

test("connectRevenueCat without Purchases warns and does nothing", () => {
  const { native } = fakeNative()
  const { Unolink } = load(native)
  Unolink.configure("ulk_key")
  expect(() => Unolink.connectRevenueCat(undefined as never)()).not.toThrow()
  expect(native.setUserId).not.toHaveBeenCalled()
})

test("signUpSkipped carries its properties", () => {
  const { native } = fakeNative()
  const { Unolink } = load(native)
  Unolink.configure("ulk_key")
  Unolink.signUpSkipped({ screen: "welcome" })
  expect(native.track).toHaveBeenCalledWith("sign_up_skipped", { screen: "welcome" })
})
