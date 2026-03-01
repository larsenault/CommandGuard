//  GatewayCommandValidator.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import Foundation

// Validates incoming command envelopes with gateway-specific stateful rules.
actor GatewayCommandValidator {
    private struct NonceEntry {
        let value: String
        let expiresAt: Date
    }

    struct ValidationOutcome {
        let envelope: CommandEnvelope
        let twinStateAfterAcceptance: DigitalTwinState
        let predictedStates: [DigitalTwinState]
        let predictionHorizonSeconds: Double
    }

    private let allowedOperatorId: String
    private let userDefaults: UserDefaults
    private let timestampTolerance: TimeInterval
    private let nonceTTL: TimeInterval
    private let nonceCapacity: Int
    private let safetyPredictionHorizonSeconds: Double = 300
    private let stateAdvanceSecondsPerAcceptedCommand: Double = 60
    private let zeroTolerance: Double = 0.0001
    private var nonces: [NonceEntry] = []

    // Persisted state keys
    private let lastRequestIdKey = "CommandGuard.Gateway.LastRequestId"
    private let lastTimestampKey = "CommandGuard.Gateway.LastTimestamp"
    private let lastSeenTimestampKey = "CommandGuard.Gateway.LastSeenTimestamp"
    private let twinTemperatureKey = "CommandGuard.Gateway.Twin.TemperatureF"
    private let twinHumidityKey = "CommandGuard.Gateway.Twin.HumidityPercent"

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
    func decodeAndValidate(payload: Data, now: Date = Date()) async throws -> ValidationOutcome {
        let (envelope, timestamp) = try await MainActor.run {
            try CommandSchemaValidator.decodeAndValidateBasics(from: payload)
        }
        defer {
            saveLastSeenTimestamp(timestamp)
        }

        // Load the latest simulated room conditions so it predicts from "now", not from scratch each time.
        let currentTwinState = await loadTwinState()
        let predictedStates = try await validateStateful(
            envelope: envelope,
            timestamp: timestamp,
            now: now,
            currentTwinState: currentTwinState
        )
        let twinStateAfterAcceptance = await recordAcceptance(
            requestId: envelope.requestId,
            timestamp: timestamp,
            nonce: envelope.nonce,
            command: envelope.command,
            currentTwinState: currentTwinState,
            now: now
        )
        return ValidationOutcome(
            envelope: envelope,
            twinStateAfterAcceptance: twinStateAfterAcceptance,
            predictedStates: predictedStates,
            predictionHorizonSeconds: safetyPredictionHorizonSeconds
        )
    }

    // Clears persisted state and in-memory nonce cache for testing resets.
    func resetState() {
        userDefaults.removeObject(forKey: lastRequestIdKey)
        userDefaults.removeObject(forKey: lastTimestampKey)
        userDefaults.removeObject(forKey: lastSeenTimestampKey)
        userDefaults.removeObject(forKey: twinTemperatureKey)
        userDefaults.removeObject(forKey: twinHumidityKey)
        nonces.removeAll()
    }

    // Records a rejected request id so sequencing keeps advancing even on failure.
    func recordRejectedRequestId(_ requestId: Int) {
        saveLastRequestId(requestId)
    }

    // Enforces allowed operator, monotonic timestamps, request sequencing, and nonce reuse.
    private func validateStateful(
        envelope: CommandEnvelope,
        timestamp: Date,
        now: Date,
        currentTwinState: DigitalTwinState
    ) async throws -> [DigitalTwinState] {
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

        // Apply physical-system policy checks and short-horizon safety prediction.
        return try await validatePhysicalSafety(command: envelope.command, currentTwinState: currentTwinState)
    }

    // Records success only after schema and signature validation succeed.
    private func recordAcceptance(
        requestId: Int,
        timestamp: Date,
        nonce: String,
        command: CommandBody,
        currentTwinState: DigitalTwinState,
        now: Date
    ) async -> DigitalTwinState {
        saveLastRequestId(requestId)
        saveLastTimestamp(timestamp)
        insertNonce(nonce, now: now)

        // Advance the twin by a larger demo window so each accepted command causes visible movement.
        // The model APIs are main-actor isolated, so go to MainActor for the math call.
        let nextTwinState = await MainActor.run {
            let projected = DigitalTwinModel.simulate(
                state: currentTwinState,
                command: command,
                seconds: stateAdvanceSecondsPerAcceptedCommand
            )
            return projected.last ?? currentTwinState
        }
        saveTwinState(nextTwinState)
        return nextTwinState
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

    // Runs command policy rules and forward prediction against safe operating bounds.
    private func validatePhysicalSafety(command: CommandBody, currentTwinState: DigitalTwinState) async throws -> [DigitalTwinState] {
        try await validatePolicyRules(command: command)
        return try await validatePredictionBounds(command: command, currentTwinState: currentTwinState)
    }

    // Enforces fan/valve constraints for power ON and OFF modes.
    private func validatePolicyRules(command: CommandBody) async throws {
        // Grab all policy constants in one place so the checks below read clearly.
        // Tuple mapping: .0 = fan ON range, .1 = valve ON range, .2 = fan OFF required value, .3 = valve OFF required value.
        let policy = await MainActor.run {
            (
                DigitalTwinModel.fanRangeWhenPowerOnPercent,
                DigitalTwinModel.valveRangeWhenPowerOnPercent,
                DigitalTwinModel.fanRequiredWhenPowerOffPercent,
                DigitalTwinModel.valveRequiredWhenPowerOffPercent
            )
        }

        if command.equipmentPower {
            if !policy.0.contains(command.fanSpeedPercent) {
                throw CommandSchemaError.fanSpeedPolicyViolation(command.fanSpeedPercent)
            }
            if !policy.1.contains(command.valvePositionPercent) {
                throw CommandSchemaError.valvePositionPolicyViolation(command.valvePositionPercent)
            }
            return
        }

        let fanDelta = abs(command.fanSpeedPercent - policy.2)
        if fanDelta > zeroTolerance {
            throw CommandSchemaError.fanMustBeZeroWhenPowerOff(command.fanSpeedPercent)
        }

        let valveDelta = abs(command.valvePositionPercent - policy.3)
        if valveDelta > zeroTolerance {
            throw CommandSchemaError.valveMustBeZeroWhenPowerOff(command.valvePositionPercent)
        }
    }

    // Simulates command effect over the 60 sec fixed horizon and rejects predicted unsafe trajectories.
    private func validatePredictionBounds(command: CommandBody, currentTwinState: DigitalTwinState) async throws -> [DigitalTwinState] {
        // Run a short "what happens next" forecast.
        // Tuple mapping: .0 = predicted future states, .1 = safe temp range, .2 = safe humidity range.
        let prediction = await MainActor.run {
            (
                DigitalTwinModel.simulate(
                    state: currentTwinState,
                    command: command,
                    seconds: safetyPredictionHorizonSeconds
                ),
                DigitalTwinModel.safeTemperatureRangeF,
                DigitalTwinModel.safeHumidityRangePercent
            )
        }

        for state in prediction.0 {
            if !prediction.1.contains(state.temperatureF) {
                throw CommandSchemaError.predictedTemperatureOutOfBounds(
                    value: state.temperatureF,
                    horizonSeconds: safetyPredictionHorizonSeconds
                )
            }
            if !prediction.2.contains(state.humidityPercent) {
                throw CommandSchemaError.predictedHumidityOutOfBounds(
                    value: state.humidityPercent,
                    horizonSeconds: safetyPredictionHorizonSeconds
                )
            }
        }

        return prediction.0
    }

    // Reads persisted twin state, defaulting to design initial conditions when absent.
    // If the gateway has never accepted a command yet, start at the baseline room conditions.
    private func loadTwinState() async -> DigitalTwinState {
        guard
            let temperature = userDefaults.object(forKey: twinTemperatureKey) as? Double,
            let humidity = userDefaults.object(forKey: twinHumidityKey) as? Double
        else {
            return await MainActor.run {
                DigitalTwinState.initial
            }
        }

        return await MainActor.run {
            DigitalTwinState(temperatureF: temperature, humidityPercent: humidity)
        }
    }

    // Persists twin state so future commands simulate from latest accepted conditions.
    private func saveTwinState(_ state: DigitalTwinState) {
        userDefaults.set(state.temperatureF, forKey: twinTemperatureKey)
        userDefaults.set(state.humidityPercent, forKey: twinHumidityKey)
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
