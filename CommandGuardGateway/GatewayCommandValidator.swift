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

    private struct EnvelopeMetadata {
        let requestId: Int
        let operatorId: String
        let nonce: String
    }

    private enum CommandForSafety {
        case operational(OperationalCommandBody)
        case enemy(EnemyCommandBody)
        case legacy(CommandBody)
    }

    enum ValidatedEnvelope {
        case operational(TypedCommandEnvelope<OperationalCommandBody>)
        case enemy(TypedCommandEnvelope<EnemyCommandBody>)
        case legacy(CommandEnvelope)

        var requestId: Int {
            switch self {
            case let .operational(envelope):
                return envelope.requestId
            case let .enemy(envelope):
                return envelope.requestId
            case let .legacy(envelope):
                return envelope.requestId
            }
        }

        var timestamp: String {
            switch self {
            case let .operational(envelope):
                return envelope.timestamp
            case let .enemy(envelope):
                return envelope.timestamp
            case let .legacy(envelope):
                return envelope.timestamp
            }
        }

        var operatorId: String {
            switch self {
            case let .operational(envelope):
                return envelope.operatorId
            case let .enemy(envelope):
                return envelope.operatorId
            case let .legacy(envelope):
                return envelope.operatorId
            }
        }

        var intent: CommandIntent {
            switch self {
            case .operational:
                return .operational
            case .enemy:
                return .enemyEmulation
            case .legacy:
                return .operational
            }
        }
    }

    struct ValidationOutcome {
        let envelope: ValidatedEnvelope
        let twinStateAfterAcceptance: DigitalTwinState
        let predictedStates: [DigitalTwinState]
        let predictionHorizonSeconds: Double
    }

    struct TwinProgress {
        let currentState: DigitalTwinState
        let predictedStates: [DigitalTwinState]
        let horizonSeconds: Double
    }

    private struct ActiveTwinRollout {
        let trajectory: [DigitalTwinState]
        var nextStepIndex: Int
    }

    private struct IntentProbe: Decodable {
        let intent: CommandIntent?
    }

    private let allowedOperatorId: String
    private let userDefaults: UserDefaults
    private let timestampTolerance: TimeInterval
    private let nonceTTL: TimeInterval
    private let nonceCapacity: Int
    private let safetyPredictionHorizonSeconds: Double = 300
    private let heartbeatSeconds: Double = 5
    private let zeroTolerance: Double = 0.0001
    private var nonces: [NonceEntry] = []
    private var activeTwinRollout: ActiveTwinRollout?

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
        let decodeResult = try await MainActor.run {
            try decodeEnvelope(from: payload)
        }
        defer {
            saveLastSeenTimestamp(decodeResult.timestamp)
        }

        // Load the latest simulated room conditions so it predicts from "now", not from scratch each time.
        let currentTwinState = await loadTwinState()
        let predictedStates = try await validateStateful(
            metadata: decodeResult.metadata,
            timestamp: decodeResult.timestamp,
            now: now,
            command: decodeResult.command,
            currentTwinState: currentTwinState
        )

        let twinStateAfterAcceptance = await recordAcceptance(
            requestId: decodeResult.metadata.requestId,
            timestamp: decodeResult.timestamp,
            nonce: decodeResult.metadata.nonce,
            currentTwinState: currentTwinState,
            predictedStates: predictedStates,
            now: now
        )

        return ValidationOutcome(
            envelope: decodeResult.envelope,
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
        activeTwinRollout = nil
    }

    // Records a rejected request id so sequencing keeps advancing even on failure.
    func recordRejectedRequestId(_ requestId: Int) {
        saveLastRequestId(requestId)
    }

    // Advances twin state by one 5-second step from the precomputed accepted-command trajectory.
    func advanceHeartbeat() -> TwinProgress? {
        guard var rollout = activeTwinRollout else {
            return nil
        }
        guard rollout.nextStepIndex < rollout.trajectory.count else {
            activeTwinRollout = nil
            return nil
        }

        let nextState = rollout.trajectory[rollout.nextStepIndex]
        rollout.nextStepIndex += 1

        let remainingStates: [DigitalTwinState]
        if rollout.nextStepIndex < rollout.trajectory.count {
            remainingStates = Array(rollout.trajectory[rollout.nextStepIndex...])
            activeTwinRollout = rollout
        } else {
            remainingStates = []
            activeTwinRollout = nil
        }

        saveTwinState(nextState)
        return TwinProgress(
            currentState: nextState,
            predictedStates: remainingStates,
            horizonSeconds: Double(remainingStates.count) * heartbeatSeconds
        )
    }

    // Decodes a payload into typed/legacy envelope plus common metadata used by stateful checks.
    private func decodeEnvelope(from payload: Data) throws -> (
        envelope: ValidatedEnvelope,
        metadata: EnvelopeMetadata,
        command: CommandForSafety,
        timestamp: Date
    ) {
        let probe: IntentProbe
        do {
            probe = try JSONDecoder().decode(IntentProbe.self, from: payload)
        } catch {
            throw CommandSchemaError.invalidJSON(reason: error.localizedDescription)
        }

        if let intent = probe.intent {
            switch intent {
            case .operational:
                let (envelope, timestamp) = try CommandSchemaValidator.decodeAndValidateOperationalBasics(from: payload)
                return (
                    envelope: .operational(envelope),
                    metadata: EnvelopeMetadata(requestId: envelope.requestId, operatorId: envelope.operatorId, nonce: envelope.nonce),
                    command: .operational(envelope.command),
                    timestamp: timestamp
                )
            case .enemyEmulation:
                let (envelope, timestamp) = try CommandSchemaValidator.decodeAndValidateEnemyBasics(from: payload)
                return (
                    envelope: .enemy(envelope),
                    metadata: EnvelopeMetadata(requestId: envelope.requestId, operatorId: envelope.operatorId, nonce: envelope.nonce),
                    command: .enemy(envelope.command),
                    timestamp: timestamp
                )
            }
        }

        // Backward compatibility for legacy envelopes that do not carry `intent`.
        let (envelope, timestamp) = try CommandSchemaValidator.decodeAndValidateBasics(from: payload)
        return (
            envelope: .legacy(envelope),
            metadata: EnvelopeMetadata(requestId: envelope.requestId, operatorId: envelope.operatorId, nonce: envelope.nonce),
            command: .legacy(envelope.command),
            timestamp: timestamp
        )
    }

    // Enforces allowed operator, monotonic timestamps, request sequencing, and nonce reuse.
    private func validateStateful(
        metadata: EnvelopeMetadata,
        timestamp: Date,
        now: Date,
        command: CommandForSafety,
        currentTwinState: DigitalTwinState
    ) async throws -> [DigitalTwinState] {
        // Reject commands from unexpected operators.
        guard metadata.operatorId == allowedOperatorId else {
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
        if metadata.requestId != expectedRequestId {
            throw CommandSchemaError.requestIdOutOfSequence(expected: expectedRequestId)
        }

        // Reject nonces already seen within the TTL window.
        purgeExpiredNonces(now: now)
        if nonces.contains(where: { $0.value == metadata.nonce }) {
            throw CommandSchemaError.nonceReused
        }

        // Apply physical-system policy checks and short-horizon safety prediction.
        return try await validatePhysicalSafety(command: command, currentTwinState: currentTwinState)
    }

    // Records success only after schema and signature validation succeed.
    private func recordAcceptance(
        requestId: Int,
        timestamp: Date,
        nonce: String,
        currentTwinState: DigitalTwinState,
        predictedStates: [DigitalTwinState],
        now: Date
    ) async -> DigitalTwinState {
        saveLastRequestId(requestId)
        saveLastTimestamp(timestamp)
        insertNonce(nonce, now: now)

        // Anchor a fixed 300-second trajectory at acceptance time, then advance along it every heartbeat.
        activeTwinRollout = ActiveTwinRollout(trajectory: predictedStates, nextStepIndex: 0)
        saveTwinState(currentTwinState)
        return currentTwinState
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
    private func validatePhysicalSafety(command: CommandForSafety, currentTwinState: DigitalTwinState) async throws -> [DigitalTwinState] {
        try await validatePolicyRules(command: command)
        return try await validatePredictionBounds(command: command, currentTwinState: currentTwinState)
    }

    // Enforces fan/valve constraints for power ON and OFF modes.
    private func validatePolicyRules(command: CommandForSafety) async throws {
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

        let actuator = extractActuatorValues(from: command)

        if actuator.power {
            if !policy.0.contains(actuator.fan) {
                throw CommandSchemaError.fanSpeedPolicyViolation(actuator.fan)
            }
            if !policy.1.contains(actuator.valve) {
                throw CommandSchemaError.valvePositionPolicyViolation(actuator.valve)
            }
            return
        }

        let fanDelta = abs(actuator.fan - policy.2)
        if fanDelta > zeroTolerance {
            throw CommandSchemaError.fanMustBeZeroWhenPowerOff(actuator.fan)
        }

        let valveDelta = abs(actuator.valve - policy.3)
        if valveDelta > zeroTolerance {
            throw CommandSchemaError.valveMustBeZeroWhenPowerOff(actuator.valve)
        }
    }

    // Simulates command effect over the fixed 300-second horizon and rejects predicted unsafe trajectories.
    private func validatePredictionBounds(command: CommandForSafety, currentTwinState: DigitalTwinState) async throws -> [DigitalTwinState] {
        // Run a short "what happens next" forecast.
        // Tuple mapping: .0 = predicted future states, .1 = safe temp range, .2 = safe humidity range.
        let prediction = await MainActor.run {
            let predictedStates: [DigitalTwinState]
            switch command {
            case let .operational(operationalCommand):
                predictedStates = DigitalTwinModel.simulate(
                    state: currentTwinState,
                    command: operationalCommand,
                    seconds: safetyPredictionHorizonSeconds
                )
            case let .enemy(enemyCommand):
                predictedStates = DigitalTwinModel.simulate(
                    state: currentTwinState,
                    command: enemyCommand,
                    seconds: safetyPredictionHorizonSeconds
                )
            case let .legacy(legacyCommand):
                predictedStates = DigitalTwinModel.simulate(
                    state: currentTwinState,
                    command: legacyCommand,
                    seconds: safetyPredictionHorizonSeconds
                )
            }
            return (
                predictedStates,
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

    private func extractActuatorValues(from command: CommandForSafety) -> (fan: Double, valve: Double, power: Bool) {
        switch command {
        case let .operational(operationalCommand):
            return (operationalCommand.fanSpeedPercent, operationalCommand.valvePositionPercent, operationalCommand.equipmentPower)
        case let .enemy(enemyCommand):
            return (enemyCommand.fanSpeedPercent, enemyCommand.valvePositionPercent, enemyCommand.equipmentPower)
        case let .legacy(legacyCommand):
            return (legacyCommand.fanSpeedPercent, legacyCommand.valvePositionPercent, legacyCommand.equipmentPower)
        }
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
