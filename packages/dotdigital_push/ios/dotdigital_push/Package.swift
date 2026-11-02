// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dotdigital_push",
    platforms: [.iOS("13.0")],
    products: [
        .library(name: "dotdigital-push", targets: ["dotdigital_push"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/comapi/comapi-sdk-ios-objc-spm", from: "2.2.0")
    ],
    targets: [
        .target(
            name: "dotdigital_push",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "CMPComapiFoundation", package: "comapi-sdk-ios-objc-spm")
            ]
        )
    ]
)