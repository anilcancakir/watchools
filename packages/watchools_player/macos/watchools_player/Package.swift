// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "watchools_player",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .library(name: "watchools-player", targets: ["watchools_player"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // MPVKit ships prebuilt xcframeworks for macOS, iOS, tvOS and visionOS
        // carrying mpv 0.41.0 and FFmpeg n8.1.2. The alternative, media_kit's
        // libs packages, is stuck on pub.dev at a 2023 libmpv and has no tvOS
        // slice at all. The default product is the LGPL build; never take
        // MPVKit-GPL, which pulls x264 and x265 in.
        //
        // The `wid` render path this plugin uses is not upstream mpv: MPVKit
        // carries 0001-player-add-moltenvk-context.patch, whose `moltenvk` gpu
        // context casts `WinID` to a CAMetalLayer. Upstream reads `WinID` in
        // four files and none of them is macOS.
        .package(url: "https://github.com/mpvkit/MPVKit.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "watchools_player",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "MPVKit", package: "MPVKit"),
            ],
            resources: [
                // If your plugin requires a privacy manifest, for example if it collects user
                // data, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
