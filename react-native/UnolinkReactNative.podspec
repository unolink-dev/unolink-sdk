require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "UnolinkReactNative"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]
  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/unolink-dev/unolink-sdk.git", :tag => "v#{s.version}" }

  # The bridge (ios/*.h, *.mm) plus the Unolink iOS SDK itself (ios/UnolinkCore, copied in by scripts/sync-native.mjs).
  s.source_files = "ios/**/*.{h,m,mm,swift}"
  s.resource_bundles = { "UnolinkPrivacy" => ["ios/UnolinkCore/PrivacyInfo.xcprivacy"] }
  s.swift_version = "5.9"
  s.pod_target_xcconfig = { "DEFINES_MODULE" => "YES" }

  install_modules_dependencies(s)
end
