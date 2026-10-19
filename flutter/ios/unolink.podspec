# Flutter plugin for Unolink. Compiles the bridge (Classes/) together with the Unolink iOS SDK itself (UnolinkCore/,
# copied in by tool/sync_native.sh), so it needs nothing from CocoaPods trunk.
Pod::Spec.new do |s|
  s.name             = 'unolink'
  s.version          = '0.2.0'
  s.summary          = 'Unolink for Flutter: install attribution and the install-to-purchase funnel.'
  s.homepage         = 'https://unolink.dev/docs'
  s.license          = { :type => 'MIT' }
  s.author           = 'Marin Capranov (Unolink)'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift', 'UnolinkCore/**/*.swift'
  s.resource_bundles = { 'UnolinkPrivacy' => ['UnolinkCore/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
