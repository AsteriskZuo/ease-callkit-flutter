// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "em_chat_callkit",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "em-chat-callkit",
            targets: ["em_chat_callkit"]
        )
    ],
    dependencies: [
        .package(
            name: "FlutterFramework",
            path: "../FlutterFramework"
        )
    ],
    targets: [
        .target(
            name: "em_chat_callkit",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/em_chat_callkit",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include/em_chat_callkit")
            ]
        )
    ]
)
