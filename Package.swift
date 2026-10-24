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
        .package(url: "https://github.com/1amageek/mac-component.git", from: "0.2.0"),
        .package(url: "https://github.com/1amageek/database-client.git", revision: "cd81942c063e4d26ac9fd5ffb002b312dbf6580b"),
        .package(
            url: "https://github.com/1amageek/database-framework.git",
            revision: "4fe236dc47d7d7ded0921caafb3d7e317d81b504"
        ),
        .package(
            url: "https://github.com/1amageek/database-kit.git",
            revision: "b325109676a4b9b3431e2e306ca8c0dcf1d9a7bf"
        ),
        .package(
            url: "https://github.com/1amageek/storage-kit.git",
            from: "26.1021.0"
        ),
    ],
    targets: [
        // UI - UI層（SwiftUI・macOS専用）+ ロジック層統合
        .target(
            name: "DatabaseStudioUI",
            dependencies: [
                .product(name: "MacComponent", package: "mac-component"),
                .product(name: "DatabaseClient", package: "database-client"),
                .product(name: "DatabaseClientHTTP", package: "database-client"),
                .product(name: "DatabaseWire", package: "database-kit"),
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
            resources: [.copy("GraphDataset/Resources/automotive.json")],
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
