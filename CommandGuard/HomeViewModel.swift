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
    @Published var temperatureSetpoint: Double = 22
    @Published var humiditySetpoint: Double = 40
    @Published var fanSpeed: Double = 50
    @Published var valvePosition: Double = 50
    @Published var equipmentPower: Bool = false
    @Published var controlEnabled: Bool = true

    @Published var sendState: SendState = .idle
    @Published var statusMessage: String? = nil
    @Published var lastResultTimestamp: Date? = nil
    @Published var recentEvents: [RecentEvent] = []

    private let sendService = CommandSendResult.CommandSendService()

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

    func sendCommand(requestId: Int, operatorId: String) async -> Int? {
        guard !isSending else {
            return nil
        }

        sendState = .sending
        statusMessage = nil
        lastResultTimestamp = nil

        let body = CommandBody(
            temperatureSetpointF: temperatureSetpoint,
            humiditySetpointPercent: humiditySetpoint,
            fanSpeedPercent: fanSpeed,
            valvePositionPercent: valvePosition,
            equipmentPower: equipmentPower,
            controlEnabled: controlEnabled
        )

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
            let canonical = try encodeCanonicalEnvelope(envelope)
            let signer = CryptoSigner()
            let (sigBase64, keyId) = try signer.sign(data: canonical)
            envelope.signature = Signature(alg: "ECDSA_P256_SHA256", value: sigBase64, keyId: keyId)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(envelope)
            if let jsonString = String(data: data, encoding: .utf8) {
                print("=== SEND COMMAND (SIGNED) ===\n\(jsonString)")
            }

            updatedRequestId += 1
        } catch {
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

        let result = await sendService.send(command: body)
        switch result {
        case let .success(response):
            sendState = .success
            statusMessage = "Gateway accepted command"
            lastResultTimestamp = response.receivedAt
            appendRecentEvent(
                title: "Success",
                details: nil,
                timestamp: response.receivedAt,
                isSuccess: true,
                command: body
            )
        case let .failure(error):
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

        return updatedRequestId
    }

    func dismissPopup() {
        sendState = .idle
        statusMessage = nil
    }

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

struct RecentEvent: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let details: String?
    let timestamp: Date
    let isSuccess: Bool
}
