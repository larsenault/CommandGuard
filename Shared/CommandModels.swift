//  CommandModels.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
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

// Schema validation errors for command envelopes and stateful gateway checks.
public enum CommandSchemaError: LocalizedError {
    case invalidJSON(reason: String)
    case invalidTimestampFormat
    case timestampNotMonotonic
    case timestampTooSoon
    case invalidRequestId
    case requestIdOutOfSequence(expected: Int)
    case emptyOperatorId
    case operatorIdNotAllowed(expected: String)
    case invalidNonce
    case nonceReused
    case temperatureOutOfRange(Double)
    case humidityOutOfRange(Double)
    case fanSpeedOutOfRange(Double)
    case valvePositionOutOfRange(Double)
    case valvePositionUnsafe(Double)
    case fanSpeedTooLowForPower(Double)
    case invalidSignatureFields

    public var errorDescription: String? {
        switch self {
        case let .invalidJSON(reason):
            return "Invalid JSON: \(reason)"
        case .invalidTimestampFormat:
            return "Invalid timestamp format"
        case .timestampNotMonotonic:
            return "Timestamp is older than the last accepted value"
        case .timestampTooSoon:
            return "Timestamp is too close to current time"
        case .invalidRequestId:
            return "Invalid request id"
        case let .requestIdOutOfSequence(expected):
            return "Request id out of sequence (expected \(expected))"
        case .emptyOperatorId:
            return "Operator id is required"
        case let .operatorIdNotAllowed(expected):
            return "Operator id not allowed (expected \(expected))"
        case .invalidNonce:
            return "Nonce is not valid Base64"
        case .nonceReused:
            return "Nonce has already been used"
        case let .temperatureOutOfRange(value):
            return "Temperature out of range: \(value)"
        case let .humidityOutOfRange(value):
            return "Humidity out of range: \(value)"
        case let .fanSpeedOutOfRange(value):
            return "Fan speed out of range: \(value)"
        case let .valvePositionOutOfRange(value):
            return "Valve position out of range: \(value)"
        case let .valvePositionUnsafe(value):
            return "Valve position unsafe: \(value)"
        case let .fanSpeedTooLowForPower(value):
            return "Fan speed too low for power ON: \(value)"
        case .invalidSignatureFields:
            return "Signature fields are invalid"
        }
    }
}

// Stateless validation for JSON shape, ranges, and basic field constraints.
public enum CommandSchemaValidator {
    // Mirrors UI ranges and percent bounds to keep gateway validation consistent.
    private static let temperatureRange = 59.0...86.0
    private static let humidityRange = 20.0...60.0
    private static let percentRange = 0.0...100.0

    // Decode JSON and validate schema-level fields that do not require gateway state.
    public static func decodeAndValidateBasics(from data: Data) throws -> (CommandEnvelope, Date) {
        let decoder = JSONDecoder()
        do {
            let envelope = try decoder.decode(CommandEnvelope.self, from: data)
            let timestamp = try validateEnvelopeBasics(envelope)
            return (envelope, timestamp)
        } catch let error as CommandSchemaError {
            throw error
        } catch {
            throw CommandSchemaError.invalidJSON(reason: error.localizedDescription)
        }
    }

    // Validates required fields, signatures fields (presence only), and command ranges.
    public static func validateEnvelopeBasics(_ envelope: CommandEnvelope) throws -> Date {
        // Request id must exist and be positive; sequencing is enforced by the gateway.
        guard envelope.requestId > 0 else {
            throw CommandSchemaError.invalidRequestId
        }
        let trimmedOperatorId = envelope.operatorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOperatorId.isEmpty else {
            throw CommandSchemaError.emptyOperatorId
        }
        // Timestamp format check happens here; monotonicity is enforced by the gateway.
        guard let timestamp = parseTimestamp(envelope.timestamp) else {
            throw CommandSchemaError.invalidTimestampFormat
        }
        // Nonce must be valid Base64; replay checks are handled by the gateway.
        guard Data(base64Encoded: envelope.nonce) != nil else {
            throw CommandSchemaError.invalidNonce
        }
        // Signature content is checked for presence here; cryptographic validation is elsewhere.
        if let signature = envelope.signature {
            if signature.alg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                signature.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                signature.keyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CommandSchemaError.invalidSignatureFields
            }
        }
        // Validate numeric ranges and safety rules on the command body.
        try validateCommandBody(envelope.command)
        return timestamp
    }

    public static func validateCommandBody(_ command: CommandBody) throws {
        // Enforce UI slider ranges and percent bounds.
        if !temperatureRange.contains(command.temperatureSetpointF) {
            throw CommandSchemaError.temperatureOutOfRange(command.temperatureSetpointF)
        }
        if !humidityRange.contains(command.humiditySetpointPercent) {
            throw CommandSchemaError.humidityOutOfRange(command.humiditySetpointPercent)
        }
        if !percentRange.contains(command.fanSpeedPercent) {
            throw CommandSchemaError.fanSpeedOutOfRange(command.fanSpeedPercent)
        }
        if !percentRange.contains(command.valvePositionPercent) {
            throw CommandSchemaError.valvePositionOutOfRange(command.valvePositionPercent)
        }
        // Safety rule: valve position above 90% is rejected.
        if command.valvePositionPercent > 90 {
            throw CommandSchemaError.valvePositionUnsafe(command.valvePositionPercent)
        }
        // Safety rule: fan must spin when power is ON.
        if command.equipmentPower, command.fanSpeedPercent < 5 {
            throw CommandSchemaError.fanSpeedTooLowForPower(command.fanSpeedPercent)
        }
    }

    public static func parseTimestamp(_ timestamp: String) -> Date? {
        // Accept fractional or non-fractional ISO 8601 timestamps.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) {
            return date
        }
        return ISO8601DateFormatter().date(from: timestamp)
    }
}
