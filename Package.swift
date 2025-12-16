// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Prance",
    platforms: [
      .macOS(.v26),
    ],
    products: [
      .executable(
        name: "Prance",
        targets: ["Prance"]),
      .library(
        name: "PranceCore",
        type: .static,
        targets: ["PranceCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/tristan-burnside/Swifty-LLVM.git", branch:"main")
    ],
    targets: [
        .target(
          name: "PranceCore",
          dependencies:[.product(name: "SwiftyLLVM", package:"Swifty-LLVM")]),
        .executableTarget(
            name: "Prance",
            dependencies: ["PranceCore"])
    ]
)
