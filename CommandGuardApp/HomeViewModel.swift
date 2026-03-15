//  HomeViewModel.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import SwiftUI
import Combine
import Foundation

enum EnemyAttackMode: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case replayNonce = "Replay Nonce"
    case invalidSignature = "Invalid Signature"

    var id: String { rawValue }
}

@MainActor
final class HomeViewModel: ObservableObject {
    // UI inputs for building a command.
    @Published var fanSpeed: Double = 50
    @Published var valvePosition: Double = 50
    @Published var equipmentPower: Bool = false
    @Published var enemyEmulation: Bool = false
    @Published var enemyTemperatureSetpoint: Double = 95
    @Published var enemyHumiditySetpoint: Double = 10
    @Published var enemyFanSpeed: Double = 120
    @Published var enemyValvePosition: Double = -10
    @Published var enemyEquipmentPower: Bool = true
    @Published var enemyAttackMode: EnemyAttackMode = .normal

    // UI state for send progress and result display.
    @Published var sendState: SendState = .idle
    @Published var statusMessage: String? = nil
    @Published var lastResultTimestamp: Date? = nil
    @Published var recentEvents: [RecentEvent] = []
    // Gateway discovery list and current selection.
    @Published var gateways: [GatewayService] = []
    @Published var selectedGatewayId: String? = nil

    // Service that will transmit the signed envelope.
    private let sendService = CommandSendResult.CommandSendService()
    private let browser = BonjourBrowser()
    private var lastAcceptedEnemyNonce: String?

    // Derived UI labels and flags.
    var statusTitle: String? { sendState.statusText }
    var isSending: Bool { sendState.isSendDisabled }
    var showsResultPopup: Bool {
        switch sendState {
        case .success, .failure:
            return true
        case .idle, .sending:
            return false
        }
    }

    var statusStyle: StatusStyle { sendState.statusStyle }
    // Resolved gateway object for the currently selected picker id.
    var selectedGateway: GatewayService? {
        gateways.first { $0.id == selectedGatewayId }
    }

    // Starts browsing for gateways and updates the picker list.
    func startBrowsing() {
        browser.start { [weak self] services in
            Task { @MainActor in
                // Refresh the picker list with the latest Bonjour results.
                self?.gateways = services
                // Clear the selection if the chosen gateway disappears.
                if let selectedId = self?.selectedGatewayId,
                   services.contains(where: { $0.id == selectedId }) == false {
                    self?.selectedGatewayId = nil
                }
            }
        }
    }

    // Stops browsing to avoid unnecessary network activity.
    func stopBrowsing() {
        browser.stop()
    }

    // Builds, signs, encodes, and sends a command. Returns the next request id on success.
    func sendCommand(requestId: Int, operatorId: String) async -> Int? {
        guard !isSending else {
            return nil
        }

        // Ensure the user picked a gateway before sending.
        guard let gateway = selectedGateway else {
            sendState = .failure(message: "No Gateway Selected")
            statusMessage = "Select a gateway before sending a command."
            lastResultTimestamp = Date()
            return nil
        }

        // Reset UI status for a new send attempt.
        sendState = .sending
        statusMessage = nil
        lastResultTimestamp = nil

        // Create the command body from UI inputs.
        let body = OperationalCommandBody(
            fanSpeedPercent: fanSpeed,
            valvePositionPercent: valvePosition,
            equipmentPower: equipmentPower,
            enemyEmulation: enemyEmulation
        )

        // Construct the envelope that will be signed and transmitted.
        var updatedRequestId = requestId
        var envelope = TypedCommandEnvelope(
            timestamp: iso8601Now(),
            requestId: requestId,
            operatorId: operatorId,
            nonce: makeNonceBase64(),
            intent: .operational,
            command: body,
            signature: nil
        )

        do {
            // Sign the canonical envelope bytes.
            let canonical = try encodeCanonicalEnvelope(envelope)
            let signer = CryptoSigner()
            let (sigBase64, keyId) = try signer.sign(data: canonical)
            envelope.signature = Signature(alg: "ECDSA_P256_SHA256", value: sigBase64, keyId: keyId)

            // Encode the signed envelope as compact JSON for NDJSON transport.
            let transportEncoder = JSONEncoder()
            transportEncoder.outputFormatting = [.sortedKeys]
            let data = try transportEncoder.encode(envelope)
            // Log a pretty-printed version for prototype debugging.
            let debugEncoder = JSONEncoder()
            debugEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let jsonString = String(data: try debugEncoder.encode(envelope), encoding: .utf8) {
                print("=== SEND COMMAND (SIGNED) ===\n\(jsonString)")
            }

            // Send the signed NDJSON payload to the selected gateway.
            let result = await sendService.send(
                signedEnvelopeData: data,
                gateway: gateway
            )
            switch result {
            case let .success(response):
                // Update UI with success result.
                let deliveryFailed = response.deliveryStatus == .failed
                let executionFailed = response.executionStatus == .failed
                let isSuccess = deliveryFailed == false && executionFailed == false
                let statusPrefix: String
                if deliveryFailed {
                    statusPrefix = "Delivery failed"
                } else if executionFailed {
                    statusPrefix = "Command failed"
                } else {
                    statusPrefix = "Command succeeded"
                }

                sendState = isSuccess ? .success : .failure(message: "Failed")
                statusMessage = response.message == nil ? statusPrefix : "\(statusPrefix): \(response.message ?? "")"

                let displayTimestamp = response.gatewayTimestamp ?? response.receivedAt
                lastResultTimestamp = displayTimestamp
                appendRecentEvent(
                    title: isSuccess ? "Success" : "Failed",
                    details: response.message == nil ? statusPrefix : "\(statusPrefix): \(response.message ?? "")",
                    timestamp: displayTimestamp,
                    isSuccess: isSuccess,
                    command: body
                )

                // Advance after any gateway response that includes a request id.
                if response.requestId > 0 {
                    updatedRequestId = response.requestId + 1
                }
            case let .failure(error):
                // Update UI with failure result.
                sendState = .failure(message: error.userTitle)
                statusMessage = error.userMessage
                lastResultTimestamp = Date()
                appendRecentEvent(
                    title: error.userTitle,
                    details: error.userMessage,
                    timestamp: Date(),
                    isSuccess: false,
                    command: body
                )
            }

            // Keep request id in sync with gateway acceptance rules.
            return updatedRequestId
        } catch {
            // Capture signing or encoding failures.
            sendState = .failure(message: "Error")
            statusMessage = "Failed to sign or encode command"
            lastResultTimestamp = Date()
            appendRecentEvent(
                title: "Error",
                details: "Failed to sign or encode command",
                timestamp: Date(),
                isSuccess: false,
                command: body
            )
            return nil
        }
    }

    // Builds, signs, encodes, and sends an enemy-emulation command payload.
    func sendEnemyCommand(requestId: Int, operatorId: String) async -> Int? {
        guard !isSending else {
            return nil
        }

        guard let gateway = selectedGateway else {
            sendState = .failure(message: "No Gateway Selected")
            statusMessage = "Select a gateway before sending a command."
            lastResultTimestamp = Date()
            return nil
        }

        sendState = .sending
        statusMessage = nil
        lastResultTimestamp = nil

        let nonce: String
        switch enemyAttackMode {
        case .normal, .invalidSignature:
            nonce = makeNonceBase64()
        case .replayNonce:
            guard let replayNonce = lastAcceptedEnemyNonce else {
                sendState = .failure(message: "Missing Replay Nonce")
                statusMessage = "Send one accepted enemy command first, then replay its nonce."
                lastResultTimestamp = Date()
                return nil
            }
            nonce = replayNonce
        }

        let body = EnemyCommandBody(
            temperatureSetpointF: enemyTemperatureSetpoint,
            humiditySetpointPercent: enemyHumiditySetpoint,
            fanSpeedPercent: enemyFanSpeed,
            valvePositionPercent: enemyValvePosition,
            equipmentPower: enemyEquipmentPower
        )

        var updatedRequestId = requestId
        var envelope = TypedCommandEnvelope(
            timestamp: iso8601Now(),
            requestId: requestId,
            operatorId: operatorId,
            nonce: nonce,
            intent: .enemyEmulation,
            command: body,
            signature: nil
        )

        do {
            let canonical = try encodeCanonicalEnvelope(envelope)
            let signer = CryptoSigner()
            let (sigBase64, keyId) = try signer.sign(data: canonical)
            var signatureValue = sigBase64
            if enemyAttackMode == .invalidSignature {
                signatureValue = tamperSignatureBase64(sigBase64)
            }
            envelope.signature = Signature(alg: "ECDSA_P256_SHA256", value: signatureValue, keyId: keyId)

            let transportEncoder = JSONEncoder()
            transportEncoder.outputFormatting = [.sortedKeys]
            let data = try transportEncoder.encode(envelope)
            let result = await sendService.send(
                signedEnvelopeData: data,
                gateway: gateway
            )

            switch result {
            case let .success(response):
                let deliveryFailed = response.deliveryStatus == .failed
                let executionFailed = response.executionStatus == .failed
                let isSuccess = deliveryFailed == false && executionFailed == false
                let statusPrefix: String
                if deliveryFailed {
                    statusPrefix = "Delivery failed"
                } else if executionFailed {
                    statusPrefix = "Command failed"
                } else {
                    statusPrefix = "Command succeeded"
                }

                sendState = isSuccess ? .success : .failure(message: "Failed")
                statusMessage = response.message == nil ? statusPrefix : "\(statusPrefix): \(response.message ?? "")"

                let displayTimestamp = response.gatewayTimestamp ?? response.receivedAt
                lastResultTimestamp = displayTimestamp
                if isSuccess {
                    lastAcceptedEnemyNonce = envelope.nonce
                }
                appendRecentEvent(
                    title: isSuccess ? "Enemy Success" : "Enemy Failed",
                    details: response.message == nil ? statusPrefix : "\(statusPrefix): \(response.message ?? "")",
                    timestamp: displayTimestamp,
                    isSuccess: isSuccess,
                    command: body
                )

                if response.requestId > 0 {
                    updatedRequestId = response.requestId + 1
                }
            case let .failure(error):
                sendState = .failure(message: error.userTitle)
                statusMessage = error.userMessage
                lastResultTimestamp = Date()
                appendRecentEvent(
                    title: "Enemy \(error.userTitle)",
                    details: error.userMessage,
                    timestamp: Date(),
                    isSuccess: false,
                    command: body
                )
            }

            return updatedRequestId
        } catch {
            sendState = .failure(message: "Error")
            statusMessage = "Failed to sign or encode enemy command"
            lastResultTimestamp = Date()
            appendRecentEvent(
                title: "Enemy Error",
                details: "Failed to sign or encode enemy command",
                timestamp: Date(),
                isSuccess: false,
                command: body
            )
            return nil
        }
    }

    private func tamperSignatureBase64(_ original: String) -> String {
        guard !original.isEmpty else {
            return "AA=="
        }
        var characters = Array(original)
        if let index = characters.firstIndex(where: { $0 != "=" }) {
            characters[index] = characters[index] == "A" ? "B" : "A"
        }
        return String(characters)
    }

    // Resets the popup state after the user dismisses it.
    func dismissPopup() {
        sendState = .idle
        statusMessage = nil
    }

    // Clears the recent event history in the UI.
    func clearRecentEvents() {
        recentEvents.removeAll()
    }

    // Adds an entry to the recent events list and trims the list size.
    private func appendRecentEvent(
        title: String,
        details: String?,
        timestamp: Date,
        isSuccess: Bool,
        command: OperationalCommandBody
    ) {
        let summary = commandSummary(for: command)
        recentEvents.insert(
            RecentEvent(
                title: title,
                summary: summary,
                details: details,
                timestamp: timestamp,
                isSuccess: isSuccess
            ),
            at: 0
        )
        if recentEvents.count > 10 {
            recentEvents.removeLast(recentEvents.count - 10)
        }
    }

    // Adds an enemy emulation event entry and trims the list size.
    private func appendRecentEvent(
        title: String,
        details: String?,
        timestamp: Date,
        isSuccess: Bool,
        command: EnemyCommandBody
    ) {
        let summary = commandSummary(for: command)
        recentEvents.insert(
            RecentEvent(
                title: title,
                summary: summary,
                details: details,
                timestamp: timestamp,
                isSuccess: isSuccess
            ),
            at: 0
        )
        if recentEvents.count > 10 {
            recentEvents.removeLast(recentEvents.count - 10)
        }
    }

    // Builds a short, user-friendly summary string for the recent list.
    private func commandSummary(for command: OperationalCommandBody) -> String {
        let powerText = command.equipmentPower ? "Power ON" : "Power OFF"
        let emulationText = command.enemyEmulation ? "Enemy Emulation ON" : "Enemy Emulation OFF"
        return String(
            format: "Fan %d, Valve %d, %@, %@",
            Int(command.fanSpeedPercent),
            Int(command.valvePositionPercent),
            powerText,
            emulationText
        )
    }

    // Builds a summary string for enemy command history entries.
    private func commandSummary(for command: EnemyCommandBody) -> String {
        let powerText = command.equipmentPower ? "Power ON" : "Power OFF"
        return String(
            format: "Enemy Temp %.1f, Humidity %.1f, Fan %.1f, Valve %.1f, %@",
            command.temperatureSetpointF,
            command.humiditySetpointPercent,
            command.fanSpeedPercent,
            command.valvePositionPercent,
            powerText
        )
    }
}

// Lightweight model for the recent commands list UI.
struct RecentEvent: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let details: String?
    let timestamp: Date
    let isSuccess: Bool
}
