// The native module's contract. React Native's codegen turns this into the iOS protocol and the Android base class.
import type { TurboModule, CodegenTypes } from "react-native"
import { TurboModuleRegistry } from "react-native"

export type NativeDeepLink = {
  deepLink: string | null
  params: CodegenTypes.UnsafeObject
  linkSlug: string | null
  clickId: string
}

export interface Spec extends TurboModule {
  configure(apiKey: string, baseUrl: string | null, logLevel: string, debug: boolean, sdkVersion: string): void
  track(name: string, properties: CodegenTypes.UnsafeObject | null): void
  purchase(amount: string, currency: string, productId: string | null, properties: CodegenTypes.UnsafeObject | null): void
  setUserId(userId: string | null): void
  flush(): void
  setEnabled(enabled: boolean): void
  getInstallId(): string | null
  readonly onDeferredDeepLink: CodegenTypes.EventEmitter<NativeDeepLink>
}

export default TurboModuleRegistry.getEnforcing<Spec>("RNUnolink")
