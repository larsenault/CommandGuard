//  GatewayInbox.swift
//  CommandGuard
//
/*
This file was developed with the assistance of generative AI tools.
All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
*/

import Foundation
import Combine

// Stores and manages decoded commands for the macOS gateway UI.
final class GatewayInbox: ObservableObject {
    enum CommandStatus {
        case accepted
        case rejected
    }

    struct CommandRecord: Identifiable {
        let id = UUID()
        let envelope: CommandEnvelope
        let status: CommandStatus
        let message: String?
        let receivedAt: Date
    }

    // Most recently accepted command (for the single-item received view).
    @Published var latestCommand: CommandEnvelope?
    // Rolling list of recent commands (newest first), including rejected attempts.
    @Published var recentCommands: [CommandRecord]

    // Initializes the inbox with optional seed data (defaults to empty).
    init(latestCommand: CommandEnvelope? = nil, recentCommands: [CommandRecord] = []) {
        self.latestCommand = latestCommand
        self.recentCommands = recentCommands
    }

    // Attempt to decode raw JSON into a CommandEnvelope and add it to the beginning of the list.
    @MainActor func append(rawJSON: String) {
        // Convert the incoming JSON string into UTF-8 data.
        guard let data = rawJSON.data(using: .utf8) else {
            return
        }

        // Decode the JSON into the shared command envelope model.
        let decoder = JSONDecoder()
        do {
            let command = try decoder.decode(CommandEnvelope.self, from: data)
            appendAccepted(envelope: command)
        } catch {
            // Ignore invalid payloads for now; we will surface errors later.
            return
        }
    }

    // Adds a pre-validated command envelope to the latest slot and recent list.
    @MainActor func appendAccepted(envelope: CommandEnvelope) {
        latestCommand = envelope
        insertRecent(envelope: envelope, status: .accepted, message: nil)
    }

    // Adds a rejected command envelope to the recent list only.
    @MainActor func appendRejected(envelope: CommandEnvelope, message: String?) {
        insertRecent(envelope: envelope, status: .rejected, message: message)
    }

    private func insertRecent(envelope: CommandEnvelope, status: CommandStatus, message: String?) {
        let record = CommandRecord(
            envelope: envelope,
            status: status,
            message: message,
            receivedAt: Date()
        )
        recentCommands.insert(record, at: 0)
        if recentCommands.count > 10 {
            recentCommands.removeLast(recentCommands.count - 10)
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
            )
        ]

        let records = samples.map {
            CommandRecord(envelope: $0, status: .accepted, message: nil, receivedAt: Date())
        }
        return GatewayInbox(latestCommand: samples.first, recentCommands: records)
    }
}
