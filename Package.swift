// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HardyFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HardyFlowCore", targets: ["HardyFlowCore"]),
        .library(name: "HardyFlowUI", targets: ["HardyFlowUI"]),
        .executable(name: "HardyFlow", targets: ["HardyFlow"]),
        .executable(name: "HardyFlowTestRunner", targets: ["HardyFlowTestRunner"])
    ],
    targets: [
        .target(
            name: "HardyFlowCore",
            dependencies: [],
            path: "Sources/HardyFlowCore"
        ),
        .target(
            name: "HardyFlowUI",
            dependencies: ["HardyFlowCore"],
            path: "Sources/HardyFlowUI"
        ),
        .executableTarget(
            name: "HardyFlow",
            dependencies: ["HardyFlowCore", "HardyFlowUI"],
            path: "Sources/HardyFlow"
        ),
        .executableTarget(
            name: "HardyFlowTestRunner",
            dependencies: ["HardyFlowCore"],
            path: "Sources/HardyFlowTestRunner"
        )
    ]
)
