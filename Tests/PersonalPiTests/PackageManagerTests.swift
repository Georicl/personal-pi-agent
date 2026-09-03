import Foundation
import Testing
@testable import PersonalPi

@Suite("Pi package management")
struct PackageManagerTests {
    @Test("Package snapshots preserve scopes, resources, overrides, and configured paths")
    func decodesPackageSnapshot() throws {
        let data = Data(#"{"type":"snapshot","packages":[{"source":"npm:example","scope":"user","filtered":true,"installedPath":"/tmp/example"}],"globalResources":[{"resourceType":"extensions","path":"/tmp/example/extensions/a.ts","enabled":true,"source":"npm:example","sourceScope":"user","origin":"package","baseDir":"/tmp/example","name":"a.ts","inherited":false,"overrideState":"load"}],"projectResources":[{"resourceType":"extensions","path":"/tmp/example/extensions/a.ts","enabled":false,"source":"npm:example","sourceScope":"user","origin":"package","baseDir":"/tmp/example","name":"a.ts","inherited":true,"overrideState":"unload"}],"globalConfiguredPaths":{"extensions":["extensions/*.ts"],"skills":[],"prompts":[],"themes":[]},"projectConfiguredPaths":{"extensions":[],"skills":[],"prompts":[],"themes":["themes/*.json"]},"errors":[]}"#.utf8)

        let snapshot = try PiPackageBridge.decodeSnapshot(data)

        #expect(snapshot.packages.count == 1)
        #expect(snapshot.packages[0].scope == .user)
        #expect(snapshot.packages[0].filtered)
        #expect(snapshot.globalResources[0].resourceType == .extensions)
        #expect(snapshot.projectResources[0].inherited)
        #expect(snapshot.projectResources[0].overrideState == .unload)
        #expect(snapshot.globalConfiguredPaths.extensions == ["extensions/*.ts"])
        #expect(snapshot.projectConfiguredPaths.themes == ["themes/*.json"])
    }

    @Test("Resource path configuration addresses every Pi resource type")
    func updatesResourcePathConfiguration() {
        var paths = PiResourcePathConfiguration.empty

        for type in PiResourceType.allCases {
            paths[type] = ["\(type.rawValue)/**"]
        }

        #expect(paths.extensions == ["extensions/**"])
        #expect(paths.skills == ["skills/**"])
        #expect(paths.prompts == ["prompts/**"])
        #expect(paths.themes == ["themes/**"])
    }

    @Test("Package bridge errors remain visible to the GUI")
    func decodesPackageBridgeFailure() {
        let data = Data(#"{"type":"result","success":false,"error":"Package source is required"}"#.utf8)

        #expect(throws: PiPackageBridgeError.self) {
            try PiPackageBridge.decodeSnapshot(data)
        }
    }
}
