// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "AnyStore",
  platforms: [
    .iOS(.v14),
    .macOS(.v11)
  ],
  products: [
    .library(
      name: "AnyStore",
      targets: ["AnyStore"]
    ),
  ],
  targets: [
    .target(
      name: "AnyStore"
    ),
    .testTarget(
      name: "AnyStoreTests",
      dependencies: ["AnyStore"]
    ),
  ]
)
