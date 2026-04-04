//  GatewayInbox.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import Foundation
import Combine

// Stores and manages decoded commands for the macOS gateway UI.
final class GatewayInbox: ObservableObject {
    enum CommandStatus {
        case accepted
        case rejected
    }

    enum CommandPayload {
        case operational(OperationalCommandBody)
        case enemy(EnemyCommandBody)
    }

    struct ModbusTCPFrames {
        let registerTransactionId: UInt16
        let registerFrameHex: String
        let powerTransactionId: UInt16
        let powerFrameHex: String
    }

    struct ReceivedCommand: Identifiable {
        let id: UUID
        let timestamp: String
        let requestId: Int
        let operatorId: String
        let intent: CommandIntent
        let payload: CommandPayload
        let modbusTCPFrames: ModbusTCPFrames?

        init(
            id: UUID = UUID(),
            timestamp: String,
            requestId: Int,
            operatorId: String,
            intent: CommandIntent,
            payload: CommandPayload,
            modbusTCPFrames: ModbusTCPFrames? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.requestId = requestId
            self.operatorId = operatorId
            self.intent = intent
            self.payload = payload
            self.modbusTCPFrames = modbusTCPFrames
        }
    }

    struct CommandRecord: Identifiable {
        let id = UUID()
        let command: ReceivedCommand
        let status: CommandStatus
        let message: String?
        let receivedAt: Date
    }

    struct TwinStatus {
        let currentState: DigitalTwinState
        let currentStateSafe: Bool
        let forecastEndState: DigitalTwinState
        let forecastSafe: Bool
        let forecastHorizonSeconds: Double
        let updatedAt: Date
    }

    // Most recently accepted command (for the single-item received view).
    @Published var latestCommand: ReceivedCommand?
    // Rolling list of recent commands (newest first), including rejected attempts.
    @Published var recentCommands: [CommandRecord]
    // Latest digital-twin status shown in the gateway dashboard.
    @Published var twinStatus: TwinStatus?

    // Initializes the inbox with optional seed data (defaults to empty).
    init(latestCommand: ReceivedCommand? = nil, recentCommands: [CommandRecord] = [], twinStatus: TwinStatus? = nil) {
        self.latestCommand = latestCommand
        self.recentCommands = recentCommands
        self.twinStatus = twinStatus
    }

    // Attempt to decode raw JSON into known envelope formats and add it to history.
    @MainActor func append(rawJSON: String) {
        guard let data = rawJSON.data(using: .utf8) else {
            return
        }

        let decoder = JSONDecoder()
        do {
            let operational = try decoder.decode(TypedCommandEnvelope<OperationalCommandBody>.self, from: data)
            appendAccepted(
                command: ReceivedCommand(
                    timestamp: operational.timestamp,
                    requestId: operational.requestId,
                    operatorId: operational.operatorId,
                    intent: .operational,
                    payload: .operational(operational.command)
                )
            )
            return
        } catch {
            // Continue probing other formats.
        }

        do {
            let enemy = try decoder.decode(TypedCommandEnvelope<EnemyCommandBody>.self, from: data)
            appendAccepted(
                command: ReceivedCommand(
                    timestamp: enemy.timestamp,
                    requestId: enemy.requestId,
                    operatorId: enemy.operatorId,
                    intent: .enemyEmulation,
                    payload: .enemy(enemy.command)
                )
            )
            return
        } catch {
            // Continue probing legacy format.
        }

        // Ignore invalid payloads for now; we will surface errors later.
        return
    }

    // Adds a pre-validated command to the latest slot and recent list.
    @MainActor func appendAccepted(command: ReceivedCommand) {
        latestCommand = command
        insertRecent(command: command, status: .accepted, message: nil)
    }

    // Adds a rejected command to the recent list only.
    @MainActor func appendRejected(command: ReceivedCommand, message: String?) {
        insertRecent(command: command, status: .rejected, message: message)
    }

    // Updates the digital twin panel with current conditions and latest horizon forecast.
    @MainActor func updateTwinStatus(currentState: DigitalTwinState, predictedStates: [DigitalTwinState], horizonSeconds: Double) {
        let safeTemperatureRange = DigitalTwinModel.safeTemperatureRangeF
        let safeHumidityRange = DigitalTwinModel.safeHumidityRangePercent

        let currentSafe = safeTemperatureRange.contains(currentState.temperatureF)
            && safeHumidityRange.contains(currentState.humidityPercent)

        let forecastSafe = predictedStates.allSatisfy {
            safeTemperatureRange.contains($0.temperatureF) && safeHumidityRange.contains($0.humidityPercent)
        }

        let forecastEndState = predictedStates.last ?? currentState
        twinStatus = TwinStatus(
            currentState: currentState,
            currentStateSafe: currentSafe,
            forecastEndState: forecastEndState,
            forecastSafe: forecastSafe,
            forecastHorizonSeconds: horizonSeconds,
            updatedAt: Date()
        )
    }

    // Clears the latest and recent command history.
    @MainActor func clearHistory() {
        latestCommand = nil
        recentCommands.removeAll()
        twinStatus = nil
    }

    private func insertRecent(command: ReceivedCommand, status: CommandStatus, message: String?) {
        let record = CommandRecord(
            command: command,
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
        let sampleCommand = ReceivedCommand(
            timestamp: "2026-02-13T15:10:12.345Z",
            requestId: 1001,
            operatorId: "operator-a",
            intent: .operational,
            payload: .operational(
                OperationalCommandBody(
                    fanSpeedPercent: 60.0,
                    valvePositionPercent: 40.0,
                    equipmentPower: true,
                    enemyEmulation: false
                )
            )
        )

        let record = CommandRecord(command: sampleCommand, status: .accepted, message: nil, receivedAt: Date())
        return GatewayInbox(latestCommand: sampleCommand, recentCommands: [record])
    }
}
