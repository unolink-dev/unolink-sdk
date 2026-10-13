// Copies the native SDK cores (../ios, ../android) into this package, so the npm package is self-contained: iOS
// compiles the Swift sources through the podspec (no CocoaPods trunk; it locks in December 2026) and Android compiles
// the Kotlin sources directly (until the Android SDK is on Maven Central). Runs on `npm pack` / `npm publish`.
import { cpSync, rmSync, mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const pkg = join(here, "..")
const repo = join(pkg, "..")

const iosCore = join(pkg, "ios/UnolinkCore")
rmSync(iosCore, { recursive: true, force: true })
mkdirSync(iosCore, { recursive: true })
cpSync(join(repo, "ios/Sources/Unolink"), iosCore, { recursive: true })

const androidCore = join(pkg, "android/src/main/java/dev/unolink/core")
rmSync(androidCore, { recursive: true, force: true })
cpSync(join(repo, "android/unolink/src/main/java/dev/unolink"), androidCore, { recursive: true })

console.log("Synced native SDK cores into the package.")
