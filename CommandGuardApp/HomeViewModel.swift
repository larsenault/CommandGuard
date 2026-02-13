//  HomeViewModel.swift
//  CommandGuard
//
/*
This file was developed with the assistance of generative AI tools.
All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
*/

import SwiftUI
import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    // UI inputs for building a command.
    @Published var temperatureSetpoint: Double = 22
    @Published var humiditySetpoint: Double = 40
    @Published var fanSpeed: Double = 50
    @Published var valvePosition: Double = 50
    @Published var equipmentPower: Bool = false
    @Published var controlEnabled: Bool = true

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
        let body = CommandBody(
            temperatureSetpointF: temperatureSetpoint,
            humiditySetpointPercent: humiditySetpoint,
            fanSpeedPercent: fanSpeed,
            valvePositionPercent: valvePosition,
            equipmentPower: equipmentPower,
            controlEnabled: controlEnabled
        )

        // Construct the envelope that will be signed and transmitted.
        var updatedRequestId = requestId
        var envelope = CommandEnvelope(
            timestamp: iso8601Now(),
            requestId: requestId,
            operatorId: operatorId,
            nonce: makeNonceBase64(),
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
                command: body,
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

            // Advance request id only after a successful send attempt.
            updatedRequestId += 1
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

    // Resets the popup state after the user dismisses it.
    func dismissPopup() {
        sendState = .idle
        statusMessage = nil
    }

    // Adds an entry to the recent events list and trims the list size.
    private func appendRecentEvent(
        title: String,
        details: String?,
        timestamp: Date,
        isSuccess: Bool,
        command: CommandBody
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
    private func commandSummary(for command: CommandBody) -> String {
        let powerText = command.equipmentPower ? "Power ON" : "Power OFF"
        let controlText = command.controlEnabled ? "Control Enabled" : "Control Disabled"
        return String(
            format: "Temp %.1f, Humidity %.1f, Fan %d, Valve %d, %@, %@",
            command.temperatureSetpointF,
            command.humiditySetpointPercent,
            Int(command.fanSpeedPercent),
            Int(command.valvePositionPercent),
            powerText,
            controlText
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
