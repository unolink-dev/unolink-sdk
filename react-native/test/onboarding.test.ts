// onboardingStep / onboardingSkipped reach the native SDK as `track` with only step, index and flow.
const mockTrack = jest.fn()
jest.mock("../src/NativeRNUnolink", () => ({ __esModule: true, default: { track: (...args: unknown[]) => mockTrack(...args) } }))

// A stand-in for React's useEffect: runs the effect when its dependencies change, like a re-render would.
let mockLastDeps: unknown[] | undefined
jest.mock("react", () => ({
  useEffect: (effect: () => void, deps: unknown[]) => {
    if (mockLastDeps && deps.every((d, i) => Object.is(d, mockLastDeps![i]))) return
    mockLastDeps = deps
    effect()
  },
}))

import { Unolink, useOnboardingStep } from "../src"

beforeEach(() => {
  mockTrack.mockClear()
  mockLastDeps = undefined
})

test("onboardingStep carries step, index and flow", () => {
  Unolink.onboardingStep("goal", { index: 1, flow: "v2" })
  expect(mockTrack).toHaveBeenCalledWith("onboarding_step", { step: "goal", index: 1, flow: "v2" })
})

test("missing index and flow are left out", () => {
  Unolink.onboardingStep("goal")
  expect(mockTrack).toHaveBeenCalledWith("onboarding_step", { step: "goal" })
})

test("onboardingSkipped has the same shape", () => {
  Unolink.onboardingSkipped("notifications", { index: 3 })
  expect(mockTrack).toHaveBeenCalledWith("onboarding_skipped", { step: "notifications", index: 3 })
})

test("useOnboardingStep sends once per screen, not on every render", () => {
  useOnboardingStep("goal", { index: 1 })
  useOnboardingStep("goal", { index: 1 })
  expect(mockTrack).toHaveBeenCalledTimes(1)
  useOnboardingStep("plan", { index: 2 })
  expect(mockTrack).toHaveBeenCalledTimes(2)
  expect(mockTrack).toHaveBeenLastCalledWith("onboarding_step", { step: "plan", index: 2 })
})

test("signIn is a returning user's sign-in, apart from signUp", () => {
  Unolink.signIn("apple")
  expect(mockTrack).toHaveBeenCalledWith("sign_in", { method: "apple" })
  Unolink.signUp("email")
  expect(mockTrack).toHaveBeenLastCalledWith("sign_up", { method: "email" })
})
