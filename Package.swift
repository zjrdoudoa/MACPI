// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MACPI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MACPICore", targets: ["MACPICore"]),
        .library(name: "MACPIAppSupport", targets: ["MACPIAppSupport"]),
        .executable(name: "macpi", targets: ["MACPI"]),
        .executable(name: "macpi-gui", targets: ["MACPIApp"])
    ],
    targets: [
        .target(
            name: "MACPICore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "MACPIAppSupport"
        ),
        .executableTarget(
            name: "MACPI",
            dependencies: ["MACPICore"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "MACPIApp",
            dependencies: ["MACPIAppSupport"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore")
            ]
        ),
        .testTarget(
            name: "MACPICoreTests",
            dependencies: ["MACPICore"]
        ),
        .testTarget(
            name: "MACPIAppSupportTests",
            dependencies: ["MACPIAppSupport"]
        )
    ]
)
