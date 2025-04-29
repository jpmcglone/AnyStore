// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "AnyStore",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .tvOS(.v17),
    .watchOS(.v10)
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
