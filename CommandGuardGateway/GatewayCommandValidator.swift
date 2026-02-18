//  GatewayCommandValidator.swift
//  CommandGuard
//
/*
This file was developed with the assistance of generative AI tools.
All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
*/

import Foundation

// Validates incoming command envelopes with gateway-specific stateful rules.
actor GatewayCommandValidator {
    private struct NonceEntry {
        let value: String
        let expiresAt: Date
    }

    private let allowedOperatorId: String
    private let userDefaults: UserDefaults
    private let timestampTolerance: TimeInterval
    private let nonceTTL: TimeInterval
    private let nonceCapacity: Int
    private var nonces: [NonceEntry] = []

    // Persisted state keys
    private let lastRequestIdKey = "CommandGuard.Gateway.LastRequestId"
    private let lastTimestampKey = "CommandGuard.Gateway.LastTimestamp"
    private let lastSeenTimestampKey = "CommandGuard.Gateway.LastSeenTimestamp"

    init(
        allowedOperatorId: String = "Luke-Arsenault",
        userDefaults: UserDefaults = .standard,
        timestampTolerance: TimeInterval = 5,
        nonceTTL: TimeInterval = 5 * 60,
        nonceCapacity: Int = 10
    ) {
        self.allowedOperatorId = allowedOperatorId
        self.userDefaults = userDefaults
        self.timestampTolerance = timestampTolerance
        self.nonceTTL = nonceTTL
        self.nonceCapacity = nonceCapacity
    }

    // Runs schema validation plus gateway state checks, then updates persisted state.
    func decodeAndValidate(payload: Data, now: Date = Date()) async throws -> CommandEnvelope {
        let (envelope, timestamp) = try await MainActor.run {
            try CommandSchemaValidator.decodeAndValidateBasics(from: payload)
        }
        defer {
            saveLastSeenTimestamp(timestamp)
        }
        try validateStateful(envelope: envelope, timestamp: timestamp, now: now)
        recordAcceptance(requestId: envelope.requestId, timestamp: timestamp, nonce: envelope.nonce, now: now)
        return envelope
    }

    // Clears persisted state and in-memory nonce cache for testing resets.
    func resetState() {
        userDefaults.removeObject(forKey: lastRequestIdKey)
        userDefaults.removeObject(forKey: lastTimestampKey)
        userDefaults.removeObject(forKey: lastSeenTimestampKey)
        nonces.removeAll()
    }

    // Records a rejected request id so sequencing keeps advancing even on failure.
    func recordRejectedRequestId(_ requestId: Int) {
        saveLastRequestId(requestId)
    }

    // Enforces allowed operator, monotonic timestamps, request sequencing, and nonce reuse.
    private func validateStateful(envelope: CommandEnvelope, timestamp: Date, now: Date) throws {
        // Reject commands from unexpected operators.
        guard envelope.operatorId == allowedOperatorId else {
            throw CommandSchemaError.operatorIdNotAllowed(expected: allowedOperatorId)
        }

        // Enforce strictly increasing timestamps and minimum spacing between all commands.
        if let lastSeenTimestamp = loadLastSeenTimestamp() {
            if timestamp <= lastSeenTimestamp {
                throw CommandSchemaError.timestampNotMonotonic
            }
            if timestamp.timeIntervalSince(lastSeenTimestamp) < timestampTolerance {
                throw CommandSchemaError.timestampTooSoon
            }
        }

        // Require a strictly sequential requestId, starting at 1000 on fresh installs.
        let expectedRequestId = (loadLastRequestId() ?? 999) + 1
        if envelope.requestId != expectedRequestId {
            throw CommandSchemaError.requestIdOutOfSequence(expected: expectedRequestId)
        }

        // Reject nonces already seen within the TTL window.
        purgeExpiredNonces(now: now)
        if nonces.contains(where: { $0.value == envelope.nonce }) {
            throw CommandSchemaError.nonceReused
        }
    }

    // Records success only after schema and signature validation succeed.
    private func recordAcceptance(requestId: Int, timestamp: Date, nonce: String, now: Date) {
        saveLastRequestId(requestId)
        saveLastTimestamp(timestamp)
        insertNonce(nonce, now: now)
    }

    // FIFO cache with TTL to prevent nonce replay while bounding memory.
    private func insertNonce(_ nonce: String, now: Date) {
        purgeExpiredNonces(now: now)
        if nonces.count >= nonceCapacity {
            let overflow = nonces.count - nonceCapacity + 1
            nonces.removeFirst(max(overflow, 0))
        }
        let entry = NonceEntry(value: nonce, expiresAt: now.addingTimeInterval(nonceTTL))
        nonces.append(entry)
    }

    // Drops expired entries first, then trims to capacity (FIFO).
    private func purgeExpiredNonces(now: Date) {
        nonces.removeAll { $0.expiresAt <= now }
        if nonces.count > nonceCapacity {
            nonces.removeFirst(nonces.count - nonceCapacity)
        }
    }

    private func loadLastRequestId() -> Int? {
        guard let value = userDefaults.object(forKey: lastRequestIdKey) as? Int else {
            return nil
        }
        return value
    }

    private func saveLastRequestId(_ value: Int) {
        userDefaults.set(value, forKey: lastRequestIdKey)
    }

    private func loadLastTimestamp() -> Date? {
        guard let value = userDefaults.object(forKey: lastTimestampKey) as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: value)
    }

    private func saveLastTimestamp(_ date: Date) {
        userDefaults.set(date.timeIntervalSince1970, forKey: lastTimestampKey)
    }

    private func loadLastSeenTimestamp() -> Date? {
        guard let value = userDefaults.object(forKey: lastSeenTimestampKey) as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: value)
    }

    private func saveLastSeenTimestamp(_ date: Date) {
        userDefaults.set(date.timeIntervalSince1970, forKey: lastSeenTimestampKey)
    }
}
