// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [
    .library(name: "LinguaCore", targets: ["LinguaCore"])
]

var targets: [Target] = [
    .target(
        name: "LinguaCore",
        path: "Sources/LinguaCore"
    ),
    .testTarget(
        name: "LinguaCoreTests",
        dependencies: ["LinguaCore"],
        path: "Tests/LinguaCoreTests",
        resources: [
            .copy("Fixtures/sample.sdlxliff"),
            .copy("Fixtures/formatting.sdlxliff")
        ]
    )
]

#if os(macOS)
products.append(.executable(name: "LinguaStudio", targets: ["LinguaStudio"]))
targets.append(
    .executableTarget(
        name: "LinguaStudio",
        dependencies: ["LinguaCore"],
        path: "Sources/LinguaStudio"
    )
)
#endif

let package = Package(
    name: "LinguaStudio",
    platforms: [
        .macOS(.v13)
    ],
    products: products,
    targets: targets
)
