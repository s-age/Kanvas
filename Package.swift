// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kanvas",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/realm/SwiftLint.git", from: "0.57.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.7.0"),
    ],
    targets: [
        // Library holding every layer (Presentation/UseCase/Domain/Repository/Infrastructure/…).
        // Both executables below link it so the MCP server drives the exact same product code as
        // the app. `App/` and `MCP/` are the two executable entry points and are excluded here.
        .target(
            name: "KanvasCore",
            path: "Sources",
            exclude: ["App", "MCP"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint"),
            ]
        ),
        // Thin @main shell — returns the public `KanvasRootScene` from KanvasCore.
        .executableTarget(
            name: "Kanvas",
            dependencies: ["KanvasCore"],
            path: "Sources/App"
        ),
        // MCP server — gives a model Read/Write access to Board/Canvas/Markdown by calling the
        // KanvasCore UseCase layer (via `KanvasMCPGateway`) over stdio.
        .executableTarget(
            name: "KanvasMCP",
            dependencies: [
                "KanvasCore",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/MCP"
        ),
        // Also depends on the KanvasMCP executable target (testable since Swift 5.5) so the
        // server's pure argument-decoding helpers (`Arguments`, `connectorDropRect`) get unit
        // coverage — main.swift's top-level code never runs under XCTest.
        .testTarget(
            name: "KanvasTests",
            dependencies: ["KanvasCore", "KanvasMCP"],
            path: "Tests"
        ),
    ]
)
