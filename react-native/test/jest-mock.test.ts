// The mock apps use in their own tests.
jest.mock("../src", () => require("../jest"))
import { Unolink } from "../src"

const mock = Unolink as typeof Unolink & { __calls: unknown[][]; __reset(): void; __emitDeferredDeepLink(link: unknown): void }

beforeEach(() => mock.__reset())

test("records calls as jest.fn and in order", () => {
  Unolink.configure("ulk_test")
  Unolink.signUp("apple")
  expect(Unolink.signUp).toHaveBeenCalledWith("apple")
  expect(mock.__calls).toEqual([["configure", "ulk_test"], ["signUp", "apple"]])
  expect(Unolink.isConfigured()).toBe(true)
})

test("deferred links behave like the real package", () => {
  const link = { deepLink: "/promo", params: {}, linkSlug: null, clickId: "c" }
  mock.__emitDeferredDeepLink(link)
  const listener = jest.fn()
  Unolink.addDeferredDeepLinkListener(listener)
  expect(listener).toHaveBeenCalledWith(link)
  expect(Unolink.getPendingDeferredDeepLink()).toEqual(link)
  Unolink.consumeDeferredDeepLink()
  expect(Unolink.getPendingDeferredDeepLink()).toBeNull()
})
