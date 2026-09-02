import Foundation
import Testing
@testable import PersonalPi

@MainActor
@Suite("Task identity")
struct TaskStoreTests {
    @Test("Later prompts in one session update the same task")
    func reusesSessionTask() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PiTaskStore(storageURL: directory.appendingPathComponent("tasks.json"))

        let firstID = store.beginOrResume(
            sessionKey: "session-1",
            title: "First prompt",
            scopeName: "Project",
            workingDirectory: "/tmp/project"
        )
        let secondID = store.beginOrResume(
            sessionKey: "session-1",
            title: "Second prompt",
            scopeName: "Project",
            workingDirectory: "/tmp/project"
        )

        #expect(firstID == secondID)
        #expect(store.tasks.count == 1)
    }
}
