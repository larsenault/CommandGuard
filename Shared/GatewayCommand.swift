import Foundation

// Lightweight model for representing a received command in the gateway UI.
struct GatewayCommand: Identifiable, Hashable {
    // Stable identifier for list diffing and selection.
    let id: UUID
    // Timestamp for when the command was received locally.
    let receivedAt: Date
    // Raw command payload (e.g., JSON string) for display or debugging.
    let commandText: String

    // Initializes a command with optional defaults for id and timestamp.
    init(id: UUID = UUID(), receivedAt: Date = Date(), commandText: String) {
        self.id = id
        self.receivedAt = receivedAt
        self.commandText = commandText
    }
}
