import Foundation

// Stores and manages decoded commands for the macOS gateway UI.
@MainActor
final class GatewayInbox: ObservableObject {
    // List of decoded command envelopes shown in the UI.
    @Published var commands: [CommandEnvelope]

    // Initializes the inbox with an optional seed list (defaults to empty).
    init(commands: [CommandEnvelope] = []) {
        self.commands = commands
    }

    // Attempts to decode raw JSON into a CommandEnvelope and prepends it to the list.
    func append(rawJSON: String) {
        // Convert the incoming JSON string into UTF-8 data.
        guard let data = rawJSON.data(using: .utf8) else {
            return
        }

        // Decode the JSON into the shared command envelope model.
        let decoder = JSONDecoder()
        do {
            let command = try decoder.decode(CommandEnvelope.self, from: data)
            // Insert at the top so the newest command appears first.
            commands.insert(command, at: 0)
        } catch {
            // Ignore invalid payloads for now; we will surface errors later.
            return
        }
    }

    // Provides sample data for previews or early UI testing.
    static func sample() -> GatewayInbox {
        // Two mocked command envelopes for quick visual validation.
        let samples: [CommandEnvelope] = [
            CommandEnvelope(
                timestamp: "2026-02-13T15:10:12.345Z",
                requestId: 1001,
                operatorId: "operator-a",
                nonce: "nonce-001",
                command: CommandBody(
                    temperatureSetpointF: 72.0,
                    humiditySetpointPercent: 45.0,
                    fanSpeedPercent: 60.0,
                    valvePositionPercent: 40.0,
                    equipmentPower: true,
                    controlEnabled: true
                )
            ),
            CommandEnvelope(
                timestamp: "2026-02-13T15:20:42.901Z",
                requestId: 1002,
                operatorId: "operator-b",
                nonce: "nonce-002",
                command: CommandBody(
                    temperatureSetpointF: 68.5,
                    humiditySetpointPercent: 50.0,
                    fanSpeedPercent: 35.0,
                    valvePositionPercent: 25.0,
                    equipmentPower: false,
                    controlEnabled: false
                )
            )
        ]

        return GatewayInbox(commands: samples)
    }
}
