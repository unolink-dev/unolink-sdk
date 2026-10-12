// swift-tools-version:5.9
// The Unolink iOS SDK. The manifest lives at the repository root because Swift Package Manager requires it; the code
// is in ios/. Add it in Xcode with File → Add Package Dependencies → https://github.com/unolink-dev/unolink-sdk
import PackageDescription

let package = Package(
    name: "Unolink",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "Unolink", targets: ["Unolink"]),
    ],
    targets: [
        .target(
            name: "Unolink",
            path: "ios/Sources/Unolink",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "UnolinkTests",
            dependencies: ["Unolink"],
            path: "ios/Tests/UnolinkTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
