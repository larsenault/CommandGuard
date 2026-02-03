//  CommandModels.swift
//  CommandGuard
//
//  Command models and helpers for building/sending control commands.

import Foundation

// Body: actual control values from the UI.
public struct CommandBody: Codable {
    public let temperatureSetpointF: Double  // Target temp (°F)
    public let humiditySetpointPercent: Double  // Target RH (%)
    public let fanSpeedPercent: Double  // Fan speed (%)
    public let valvePositionPercent: Double  // Valve position (%)
    public let equipmentPower: Bool  // Power on/off
    public let controlEnabled: Bool  // Enable/disable control

    // Memberwise initializer.
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

// Envelope: metadata and body.
public struct CommandEnvelope: Codable {
    public let timestamp: String  // ISO 8601 UTC creation time
    public let requestId: Int  // Monotonic request number (1001, 1002, ...)
    public let operatorId: String  // Operator identity
    public let nonce: String  // Random Base64 nonce per command
    public let command: CommandBody  // Control body
    public var signature: Signature?  // Signature (added after signing)

    // Build an envelope; `signature` is nil until after signing.
    public init(timestamp: String, requestId: Int, operatorId: String, nonce: String, command: CommandBody, signature: Signature? = nil) {
        self.timestamp = timestamp
        self.requestId = requestId
        self.operatorId = operatorId
        self.nonce = nonce
        self.command = command
        self.signature = signature
    }
}

// Helper: current time in ISO 8601 (UTC, fractional seconds).
public func iso8601Now() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

// Helper: cryptographically secure random nonce (Base64), default 16 bytes.
public func makeNonceBase64(byteCount: Int = 16) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
    precondition(status == errSecSuccess, "Failed to generate nonce")
    return Data(bytes).base64EncodedString()
}

// Canonical JSON (sorted keys, no pretty print) for signing: envelope without signature.
public func encodeCanonicalEnvelope(_ envelope: CommandEnvelope) throws -> Data {
    var copy = envelope
    copy.signature = nil // Exclude signature from the bytes-to-sign
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(copy)
}

// Signature info embedded in the envelope (Option A).
public struct Signature: Codable {
    public let alg: String  // e.g., "ECDSA_P256_SHA256"
    public let value: String  // Base64 DER-encoded signature
    public let keyId: String  // Which key to verify with

    // Memberwise initializer.
    public init(alg: String, value: String, keyId: String) {
        self.alg = alg
        self.value = value
        self.keyId = keyId
    }
}

