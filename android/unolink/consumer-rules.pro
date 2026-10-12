# Keep the public API (callable from Java, React Native and Flutter bridges).
-keep class dev.unolink.Unolink { public *; }
-keep class dev.unolink.UnolinkOptions { public *; }
-keep class dev.unolink.UnolinkDeepLink { public *; }
-keep interface dev.unolink.DeferredDeepLinkListener { *; }
-keep enum dev.unolink.LogLevel { *; }
