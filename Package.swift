// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DatabaseStudio",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "DatabaseStudioUI", targets: ["DatabaseStudioUI"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/1amageek/database-framework.git",
            from: "26.0905.0"
        ),
        .package(
            url: "https://github.com/1amageek/database-kit.git",
            from: "26.0809.4"
        ),
        .package(
            url: "https://github.com/1amageek/storage-kit.git",
            from: "26.0807.0"
        ),
    ],
    targets: [
        // UI - UI層（SwiftUI・macOS専用）+ ロジック層統合
        .target(
            name: "DatabaseStudioUI",
            dependencies: [
                .product(name: "DatabaseEngine", package: "database-framework"),
                .product(name: "GraphIndex", package: "database-framework"),
                .product(name: "OntologyIndex", package: "database-framework"),
                .product(name: "DatabaseKit", package: "database-kit"),
                .product(name: "StorageKit", package: "storage-kit"),
                .product(name: "StorageKitSystemClock", package: "storage-kit"),
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
            name: "DatabaseStudioStateTests",
            dependencies: ["DatabaseStudioUI"],
            linkerSettings: [
                .unsafeFlags(["-L/usr/local/lib"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/usr/local/lib"])
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
