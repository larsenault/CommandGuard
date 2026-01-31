//  CommandModels.swift
//  CommandGuard
//
//  Shared command models and utilities for building control commands. Includes the signature information. 

import Foundation

public struct CommandBody: Codable {
    public let temperatureSetpointF: Double
    public let humiditySetpointPercent: Double
    public let fanSpeedPercent: Double
    public let valvePositionPercent: Double
    public let equipmentPower: Bool
    public let controlEnabled: Bool

    public init(
        temperatureSetpointF: Double,
        humiditySetpointPercent: Double,
        fanSpeedPercent: Double,
        valvePositionPercent: Double,
        equipmentPower: Bool,
        controlEnabled: Bool
    ) {
        self.temperatureSetpointF = temperatureSetpointF
        self.humiditySetpointPercent = humiditySetpointPercent
        self.fanSpeedPercent = fanSpeedPercent
        self.valvePositionPercent = valvePositionPercent
        self.equipmentPower = equipmentPower
        self.controlEnabled = controlEnabled
    }
}

public struct CommandEnvelope: Codable {
    public let timestamp: String
    public let requestId: Int
    public let operatorId: String
    public let command: CommandBody
    public var signature: Signature?

    public init(timestamp: String, requestId: Int, operatorId: String, command: CommandBody, signature: Signature? = nil) {
        self.timestamp = timestamp
        self.requestId = requestId
        self.operatorId = operatorId
        self.command = command
        self.signature = signature
    }
}

public func iso8601Now() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}
public struct Signature: Codable {
    public let alg: String
    public let value: String
    public let keyId: String

    public init(alg: String, value: String, keyId: String) {
        self.alg = alg
        self.value = value
        self.keyId = keyId
    }
}

