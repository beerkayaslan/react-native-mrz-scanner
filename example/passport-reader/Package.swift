// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PassportReaderModule",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "PassportReaderModule",
            targets: ["PassportReaderModule"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/AndyQ/NFCPassportReader.git", from: "2.1.2"),
    ],
    targets: [
        .target(
            name: "PassportReaderModule",
            dependencies: [
                .product(name: "NFCPassportReader", package: "NFCPassportReader"),
            ],
            path: "ios"
        )
    ]
)
