import Foundation

struct PersonalPiPluginArtifact: Codable, Hashable, Sendable {
    let kind: String
    let schemaVersion: Int
    let renderer: String
}

struct PersonalPiPluginGUI: Codable, Hashable, Sendable {
    let toolbarButton: Bool
    let artifactSidebar: Bool
}

struct PersonalPiPluginManifest: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let id: String
    let displayName: String
    let command: String
    let artifacts: [PersonalPiPluginArtifact]
    let settingsNamespace: String
    let gui: PersonalPiPluginGUI
}

struct BundledPiPlugin: Hashable, Sendable, Identifiable {
    let rootURL: URL
    let manifest: PersonalPiPluginManifest

    var id: String { manifest.id }
}

enum PersonalPiPluginRegistry {
    private struct PiPackageManifest: Decodable {
        struct Resources: Decodable {
            let extensions: [String]
            let skills: [String]?
        }

        let pi: Resources
    }

    static func discover() -> [BundledPiPlugin] {
        let fileManager = FileManager.default
        var roots: [URL] = []
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("PiPackages", isDirectory: true) {
            roots.append(bundled)
        }
        roots.append(
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Resources/PiPackages", isDirectory: true)
        )

        var seen = Set<String>()
        return roots.flatMap { discover(in: $0, fileManager: fileManager) }
            .filter { seen.insert($0.manifest.id).inserted }
            .sorted { $0.manifest.id < $1.manifest.id }
    }

    static func discover(
        in packagesRoot: URL,
        fileManager: FileManager = .default
    ) -> [BundledPiPlugin] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: packagesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return children.compactMap { load(at: $0, fileManager: fileManager) }
    }

    static func load(
        at packageRoot: URL,
        fileManager: FileManager = .default
    ) -> BundledPiPlugin? {
        let manifestURL = packageRoot.appendingPathComponent("personal-pi-plugin.json")
        let packageURL = packageRoot.appendingPathComponent("package.json")
        guard fileManager.fileExists(atPath: packageURL.path),
              let packageData = try? Data(contentsOf: packageURL),
              let package = try? JSONDecoder().decode(PiPackageManifest.self, from: packageData),
              !package.pi.extensions.isEmpty,
              package.pi.extensions.allSatisfy({
                  fileManager.fileExists(atPath: packageRoot.appendingPathComponent($0).path)
              }),
              (package.pi.skills ?? []).allSatisfy({
                  fileManager.fileExists(atPath: packageRoot.appendingPathComponent($0).path)
              }),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PersonalPiPluginManifest.self, from: manifestData),
              manifest.schemaVersion == 1,
              !manifest.id.isEmpty,
              !manifest.displayName.isEmpty,
              !manifest.command.isEmpty,
              !manifest.settingsNamespace.isEmpty else { return nil }
        return BundledPiPlugin(rootURL: packageRoot.standardizedFileURL, manifest: manifest)
    }
}
