// The server's rules for events (backend SdkEvents / OnboardingRules / IngestionService), checked on the device in
// development only, so a mistake shows in the console while you build instead of as a rejected event later. The
// server stays the judge: these never block a call, they only warn.

const NAME = /^[A-Za-z][A-Za-z0-9_.]{0,63}$/
export const MAX_PROPERTIES = 20
export const MAX_KEY_LENGTH = 64
export const MAX_STRING_LENGTH = 200
export const MAX_PROPERTIES_BYTES = 4096
export const MAX_USER_ID_LENGTH = 256
const ONBOARDING_KEYS = new Set(["step", "index", "flow"])

export type Properties = Record<string, string | number | boolean>

/** Problems the server would reject this event for (empty: fine). */
export function eventProblems(name: string, properties: Properties | null | undefined): string[] {
  const problems: string[] = []
  if (!NAME.test(name)) problems.push(`"${name}" isn't a valid event name: letters, digits, _ and . (at most 64), starting with a letter.`)
  if (!properties) return problems
  const keys = Object.keys(properties)
  if (keys.length > MAX_PROPERTIES) problems.push(`"${name}" has ${keys.length} properties; at most ${MAX_PROPERTIES}.`)
  for (const key of keys) {
    const value = properties[key] as unknown
    if (key.length < 1 || key.length > MAX_KEY_LENGTH) problems.push(`"${name}": property name "${key}" must be 1 to ${MAX_KEY_LENGTH} characters.`)
    if (typeof value === "string" && value.length > MAX_STRING_LENGTH)
      problems.push(`"${name}": property "${key}" is ${value.length} characters; at most ${MAX_STRING_LENGTH}.`)
    else if (typeof value === "number" && !Number.isFinite(value)) problems.push(`"${name}": property "${key}" isn't a finite number.`)
    else if (typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean")
      problems.push(`"${name}": property "${key}" must be a string, number or boolean.`)
  }
  if (utf8Length(JSON.stringify(properties)) > MAX_PROPERTIES_BYTES) problems.push(`"${name}": properties are over ${MAX_PROPERTIES_BYTES} bytes.`)
  return problems
}

/** Problems with an onboarding screen event (step and flow are fixed screen IDs, never user data). */
export function onboardingProblems(name: string, properties: Properties): string[] {
  const problems: string[] = []
  for (const key of Object.keys(properties))
    if (!ONBOARDING_KEYS.has(key)) problems.push(`${name} takes only step, index and flow, not "${key}".`)
  for (const key of ["step", "flow"] as const) {
    const value = properties[key]
    if (value === undefined && key === "flow") continue
    if (typeof value !== "string" || !NAME.test(value))
      problems.push(`${name}: ${key} "${String(value)}" must be a screen ID: letters, digits, _ and . (at most 64), starting with a letter. Not "-".`)
  }
  const index = properties.index
  if (index !== undefined && !(typeof index === "number" && Number.isInteger(index) && index >= 0 && index <= 999))
    problems.push(`${name}: index must be a whole number from 0 to 999.`)
  return problems
}

function utf8Length(text: string): number {
  let bytes = 0
  for (const ch of text) {
    const code = ch.codePointAt(0)!
    bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4
  }
  return bytes
}
