// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Runestone",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "Runestone", targets: ["Runestone"])
    ],
    dependencies: [
        // Forked to bradenacurtis801/tree-sitter at v0.20.10: fixes an Xcode 26 /
        // Swift 6.3 C++ interop compile error in api.h/parser.h (std headers
        // #include'd inside an extern "C" block). Same code otherwise.
        // See https://github.com/tree-sitter/tree-sitter/issues/5523
        .package(url: "https://github.com/bradenacurtis801/tree-sitter", .upToNextMinor(from: "0.20.9"))
    ],
    targets: [
        .target(name: "Runestone", dependencies: [
            .product(name: "TreeSitter", package: "tree-sitter")
        ], resources: [
            .copy("PrivacyInfo.xcprivacy"),
            .process("TextView/Appearance/Theme.xcassets")
        ]),
        .target(name: "TestTreeSitterLanguages", cSettings: [
            .unsafeFlags(["-w"])
        ]),
        .testTarget(name: "RunestoneTests", dependencies: [
            "Runestone",
            "TestTreeSitterLanguages"
        ])
    ]
)
