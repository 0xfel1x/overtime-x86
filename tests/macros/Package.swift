// swift-tools-version: 5.9
import PackageDescription

// Uses the public macros of the newer SDKs, one file per framework, so that a build
// with the prepared Xcode shows which macros work on Intel. See run.sh.
let package = Package(
    name: "MacroCheck",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MacroCheck", targets: ["MacroCheck"])],
    // A resource, so that #bundle has a resource bundle to point to.
    targets: [.target(name: "MacroCheck", resources: [.process("Resources")])]
)
