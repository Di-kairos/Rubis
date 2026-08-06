import Foundation
import Testing

/// Enforces the package dependency rule from SPEC §3.1.
/// Parses every Packages/*/Package.swift; any dependency outside the allowed
/// set is a build error by policy.
struct ArchitectureTests {
    /// package name → allowed local package dependencies
    static let allowedDependencies: [String: Set<String>] = [
        "EscapementCore": [],
        "DesignSystem": [],
        "PlaybackEngine": ["EscapementCore"],
        "MusicLibrary": ["EscapementCore"],
        "SubsonicKit": ["EscapementCore"],
    ]

    static var packagesRoot: URL {
        // …/Packages/EscapementCore/Tests/EscapementCoreTests/ArchitectureTests.swift → …/Packages
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // EscapementCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // EscapementCore
            .deletingLastPathComponent()  // Packages
    }

    @Test func allPackagesExist() throws {
        for name in Self.allowedDependencies.keys {
            let manifest = Self.packagesRoot
                .appendingPathComponent(name)
                .appendingPathComponent("Package.swift")
            #expect(
                FileManager.default.fileExists(atPath: manifest.path),
                "Missing package \(name)")
        }
    }

    @Test func dependencyRuleHolds() throws {
        for (name, allowed) in Self.allowedDependencies {
            let manifest = Self.packagesRoot
                .appendingPathComponent(name)
                .appendingPathComponent("Package.swift")
            let source = try String(contentsOf: manifest, encoding: .utf8)

            // local package references: .package(path: "../Name")
            let referenced = Self.localPackageReferences(in: source)
            #expect(
                referenced.subtracting(allowed).isEmpty,
                "\(name) depends on \(referenced.subtracting(allowed)) — violates SPEC §3.1")
        }
    }

    @Test func corePackagesDoNotImportUI() throws {
        // EscapementCore must never import SwiftUI/AppKit (SPEC §3.1).
        let sources = Self.packagesRoot
            .appendingPathComponent("EscapementCore/Sources")
        let files = try Self.swiftFiles(under: sources)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for banned in ["import SwiftUI", "import AppKit"] {
                #expect(
                    !source.contains(banned),
                    "\(file.lastPathComponent) contains '\(banned)'")
            }
        }
    }

    private static func localPackageReferences(in manifest: String) -> Set<String> {
        var result: Set<String> = []
        let pattern = #/\.package\(\s*path:\s*"\.\./([A-Za-z]+)"/#
        for match in manifest.matches(of: pattern) {
            result.insert(String(match.1))
        }
        return result
    }

    private static func swiftFiles(under root: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
