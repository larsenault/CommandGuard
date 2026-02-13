//  CommandModels.swift
//  CommandGuard
//
/*
This file was developed with the assistance of generative AI tools.
All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
*/

//  Shared command models and helpers for building/sending/receiving control commands.

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
    var bytes = [UInt8](repeating: 0, count: byteCount) // Build a 16 byte array of 0's initially
    let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) // Put 16 random numbers in place of the 0's from before. If succeeded mark true or false is fail
    precondition(status == errSecSuccess, "Failed to generate nonce") // Check the status of from before and if success, continue. Else, give error message
    return Data(bytes).base64EncodedString() // Return the 16 byte array as a 16 digit nonce base64 encoded
}

// Canonical JSON (sorted keys, no pretty print) for signing: envelope without signature.
public func encodeCanonicalEnvelope(_ envelope: CommandEnvelope) throws -> Data {
    var copy = envelope // Make a copy of the envelope to change
    copy.signature = nil // Exclude signature from the bytes-to-sign
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys] // Sort the JSON alphabetically every time
    return try encoder.encode(copy) // Raw bytes of the JSON which I sign
}

// Signature info embedded in the envelope (Option A).
public struct Signature: Codable {
    public let alg: String  // ECDSA_P256_SHA256
    public let value: String  // Base64 encoded signature
    public let keyId: String  // Which key to verify with

    // Memberwise initializer.
    public init(alg: String, value: String, keyId: String) {
        self.alg = alg
        self.value = value
        self.keyId = keyId
    }
}
