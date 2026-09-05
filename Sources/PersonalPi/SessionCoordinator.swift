import Foundation
import Combine

/// Pi can execute several turns, retries and continuations for one user task.
struct PiRunLifecycle {
    enum Phase { case idle, running, waiting }
    private(set) var phase: Phase = .idle
    var isActive: Bool { phase != .idle }

    mutating func receive(_ event: String) {
        switch event {
        case "command_start", "agent_start", "turn_start", "tool_execution_start", "message_update": phase = .running
        case "extension_ui_request": phase = .waiting
        case "command_finished", "agent_settled", "disconnected": phase = .idle
        default: break
        }
    }
}

/// Owns connection/run state. AppState forwards observation without duplicating it.
@MainActor
final class PiSessionCoordinator: ObservableObject {
    let client: PiRPCClient
    @Published var connectionState: PiConnectionState = .ready
    @Published var isConnected = false
    @Published var isGenerating = false
    private(set) var revision = UUID()
    private var lifecycle = PiRunLifecycle()

    init(client: PiRPCClient = PiRPCClient()) { self.client = client }

    func beginConnection() -> UUID {
        revision = UUID()
        connectionState = .connecting
        return revision
    }

    func invalidateConnection() { revision = UUID() }

    func receive(_ event: String) {
        lifecycle.receive(event)
        isGenerating = lifecycle.isActive
    }
}
