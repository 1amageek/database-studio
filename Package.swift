// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DatabaseStudio",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DatabaseStudioUI", targets: ["DatabaseStudioUI"]),
    ],
    dependencies: [
        .package(path: "../database-framework"),
        .package(path: "../database-kit"),
        .package(path: "../storage-kit"),
    ],
    targets: [
        // UI - UI層（SwiftUI・macOS専用）+ ロジック層統合
        .target(
            name: "DatabaseStudioUI",
            dependencies: [
                .product(name: "DatabaseEngine", package: "database-framework"),
                .product(name: "DatabaseCLICore", package: "database-framework"),
                .product(name: "GraphIndex", package: "database-framework"),
                .product(name: "Graph", package: "database-kit"),
                .product(name: "StorageKit", package: "storage-kit"),
                .product(name: "FDBStorage", package: "storage-kit"),
                .product(name: "SQLiteStorage", package: "storage-kit"),
            ],
            path: "Sources/DatabaseStudioUI",
            linkerSettings: [
                .unsafeFlags(["-L/usr/local/lib"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/usr/local/lib"])
            ]
        ),
        .testTarget(
            name: "GraphDocumentTests",
            dependencies: ["DatabaseStudioUI"],
            linkerSettings: [
                .unsafeFlags(["-L/usr/local/lib"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/usr/local/lib"])
            ]
        ),
        .testTarget(
            name: "AppViewModelTests",
            dependencies: ["DatabaseStudioUI"],
            linkerSettings: [
                .unsafeFlags(["-L/usr/local/lib"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/usr/local/lib"])
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
