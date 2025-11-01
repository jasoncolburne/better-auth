// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BetterAuthBasicExample",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "BetterAuthBasicExample",
            targets: ["BetterAuthBasicExample"]
        ),
    ],
    dependencies: [
        .package(path: "../../../../implementations/better-auth-swift"),
        .package(url: "https://github.com/nixberg/blake3-swift.git", from: "0.1.2"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "BetterAuthBasicExample",
            dependencies: [
                .product(name: "BetterAuth", package: "better-auth-swift"),
                .product(name: "BLAKE3", package: "blake3-swift"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources"
        ),
    ]
)
