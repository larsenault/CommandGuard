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
@MainActor
final class GatewayCommandValidator {
    // Tracks accepted nonces and their expiration so replay checks can be time-bounded.
    private struct NonceEntry {
        let value: String
        let expiresAt: Date
    }

    // Canonical subset of envelope fields required for stateful security validation.
    private struct EnvelopeMetadata {
        let requestId: Int
        let operatorId: String
        let nonce: String
    }

    // Normalized command representation so safety checks can handle typed envelope variants uniformly.
    private enum CommandForSafety {
        case operational(OperationalCommandBody)
        case enemy(EnemyCommandBody)
    }

    // Typed wrapper around supported envelope formats used after successful decode.
    enum ValidatedEnvelope {
        case operational(TypedCommandEnvelope<OperationalCommandBody>)
        case enemy(TypedCommandEnvelope<EnemyCommandBody>)

        // Exposes request ID without callers needing to branch on envelope format.
        var requestId: Int {
            switch self {
            case let .operational(envelope):
                return envelope.requestId
            case let .enemy(envelope):
                return envelope.requestId
            }
        }

        // Exposes the signed timestamp string directly from the decoded envelope.
        var timestamp: String {
            switch self {
            case let .operational(envelope):
                return envelope.timestamp
            case let .enemy(envelope):
                return envelope.timestamp
            }
        }

        // Exposes operator identity uniformly across typed payloads.
        var operatorId: String {
            switch self {
            case let .operational(envelope):
                return envelope.operatorId
            case let .enemy(envelope):
                return envelope.operatorId
            }
        }

        // Exposes declared intent for downstream analytics/routing.
        var intent: CommandIntent {
            switch self {
            case .operational:
                return .operational
            case .enemy:
                return .enemyEmulation
            }
        }
    }

    // Full result of decode + stateful checks, including simulation output for later commitment.
    struct ValidationOutcome {
        let envelope: ValidatedEnvelope
        // Metadata is carried through validation so acceptance can be committed later.
        let requestId: Int
        let timestamp: Date
        let nonce: String
        // Snapshot state used when computing the prediction before signature verification.
        let twinStateAfterAcceptance: DigitalTwinState
        let predictedStates: [DigitalTwinState]
        let predictionHorizonSeconds: Double
    }

    // Snapshot of current twin conditions plus any queued rollout states still to be applied.
    struct TwinProgress {
        let currentState: DigitalTwinState
        let predictedStates: [DigitalTwinState]
        let horizonSeconds: Double
    }

    // Captures an accepted command's precomputed trajectory and where heartbeat playback is currently positioned.
    private struct ActiveTwinRollout {
        let trajectory: [DigitalTwinState]
        var nextStepIndex: Int
    }

    // Lightweight decode pass used to choose the correct schema decoder by declared intent.
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
    private static let securityTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Persisted state keys
    private let lastRequestIdKey = "CommandGuard.Gateway.LastRequestId"
    private let lastTimestampKey = "CommandGuard.Gateway.LastTimestamp"
    private let lastSeenTimestampKey = "CommandGuard.Gateway.LastSeenTimestamp"
    private let twinTemperatureKey = "CommandGuard.Gateway.Twin.TemperatureF"
    private let twinHumidityKey = "CommandGuard.Gateway.Twin.HumidityPercent"

    // Configures security tolerances and persistence dependencies for production or test injection.
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
        let decodeResult = try decodeEnvelope(from: payload)
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

        return ValidationOutcome(
            envelope: decodeResult.envelope,
            requestId: decodeResult.metadata.requestId,
            timestamp: decodeResult.timestamp,
            nonce: decodeResult.metadata.nonce,
            twinStateAfterAcceptance: currentTwinState,
            predictedStates: predictedStates,
            predictionHorizonSeconds: safetyPredictionHorizonSeconds
        )
    }

    // Commits acceptance state only after signature verification succeeds.
    func acceptValidatedCommand(_ outcome: ValidationOutcome, now: Date = Date()) async -> DigitalTwinState {
        await recordAcceptance(
            requestId: outcome.requestId,
            timestamp: outcome.timestamp,
            nonce: outcome.nonce,
            currentTwinState: outcome.twinStateAfterAcceptance,
            predictedStates: outcome.predictedStates,
            now: now
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

    // Resets only the digital twin runtime/persisted state to baseline.
    func resetTwinState() {
        userDefaults.removeObject(forKey: twinTemperatureKey)
        userDefaults.removeObject(forKey: twinHumidityKey)
        activeTwinRollout = nil
    }

    // Records a rejected request id so sequencing keeps advancing even on failure.
    func recordRejectedRequestId(_ requestId: Int) {
        saveLastRequestId(requestId)
    }

    // Returns current twin state plus remaining rollout horizon for initial UI hydration.
    func currentTwinProgress() async -> TwinProgress {
        let currentState = await loadTwinState()

        let remainingStates: [DigitalTwinState]
        if let rollout = activeTwinRollout, rollout.nextStepIndex < rollout.trajectory.count {
            remainingStates = Array(rollout.trajectory[rollout.nextStepIndex...])
        } else {
            remainingStates = []
        }

        return TwinProgress(
            currentState: currentState,
            predictedStates: remainingStates,
            horizonSeconds: Double(remainingStates.count) * heartbeatSeconds
        )
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

        throw CommandSchemaError.invalidJSON(reason: "Missing command intent")
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
                logSecurityFailure(
                    "request \(metadata.requestId): timestamp replay/non-monotonic. received=\(formatTimestamp(timestamp)) previous=\(formatTimestamp(lastSeenTimestamp))"
                )
                throw CommandSchemaError.timestampNotMonotonic
            }
            if timestamp.timeIntervalSince(lastSeenTimestamp) < timestampTolerance {
                let delta = timestamp.timeIntervalSince(lastSeenTimestamp)
                logSecurityFailure(
                    "request \(metadata.requestId): timestamp spacing violation. received=\(formatTimestamp(timestamp)) previous=\(formatTimestamp(lastSeenTimestamp)) delta=\(String(format: "%.3f", delta))s min=\(String(format: "%.3f", timestampTolerance))s"
                )
                throw CommandSchemaError.timestampTooSoon
            }
        }

        // Require a strictly sequential requestId, starting at 1000 on fresh installs.
        let expectedRequestId = (loadLastRequestId() ?? 999) + 1
        if metadata.requestId != expectedRequestId {
            logSecurityFailure(
                "request \(metadata.requestId): requestId out of sequence. received=\(metadata.requestId) expected=\(expectedRequestId)"
            )
            throw CommandSchemaError.requestIdOutOfSequence(expected: expectedRequestId)
        }

        // Reject nonces already seen within the TTL window.
        purgeExpiredNonces(now: now)
        if let matchingEntry = nonces.first(where: { $0.value == metadata.nonce }) {
            let previousNonce = nonces.last?.value ?? "<none>"
            logSecurityFailure(
                "request \(metadata.requestId): nonce replay detected. received=\(metadata.nonce) previousAccepted=\(previousNonce) matchingNonce=\(matchingEntry.value) matchingExpiresAt=\(formatTimestamp(matchingEntry.expiresAt)) cacheCount=\(nonces.count)"
            )
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
        // Power-off actuator constraints apply to both operational and enemy commands.
        try validatePowerOffActuatorRule(command: command)

        // Enemy emulation bypasses power-on actuator policy checks, but still must pass forecast safety bounds.
        if case .enemy = command {
            return try await validatePredictionBounds(command: command, currentTwinState: currentTwinState)
        }
        try await validatePolicyRules(command: command)
        return try await validatePredictionBounds(command: command, currentTwinState: currentTwinState)
    }

    // Enforces that fan and valve must both be zero whenever equipment power is off.
    private func validatePowerOffActuatorRule(command: CommandForSafety) throws {
        let actuator = extractActuatorValues(from: command)
        guard actuator.power == false else {
            return
        }

        if abs(actuator.fan) > zeroTolerance {
            throw CommandSchemaError.fanMustBeZeroWhenPowerOff(actuator.fan)
        }
        if abs(actuator.valve) > zeroTolerance {
            throw CommandSchemaError.valveMustBeZeroWhenPowerOff(actuator.valve)
        }
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
            (
                predictStatesSync(command: command, currentTwinState: currentTwinState),
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

    // Async wrapper for running prediction on MainActor where model APIs are consumed.
    private func predictStates(command: CommandForSafety, currentTwinState: DigitalTwinState) async -> [DigitalTwinState] {
        await MainActor.run {
            predictStatesSync(command: command, currentTwinState: currentTwinState)
        }
    }

    // Shared trajectory simulator used by both strict validation and enemy-emulation bypass path.
    private func predictStatesSync(command: CommandForSafety, currentTwinState: DigitalTwinState) -> [DigitalTwinState] {
        switch command {
        case let .operational(operationalCommand):
            return DigitalTwinModel.simulate(
                state: currentTwinState,
                command: operationalCommand,
                seconds: safetyPredictionHorizonSeconds
            )
        case let .enemy(enemyCommand):
            return DigitalTwinModel.simulate(
                state: currentTwinState,
                command: enemyCommand,
                seconds: safetyPredictionHorizonSeconds
            )
        }
    }

    private func extractActuatorValues(from command: CommandForSafety) -> (fan: Double, valve: Double, power: Bool) {
        switch command {
        case let .operational(operationalCommand):
            return (operationalCommand.fanSpeedPercent, operationalCommand.valvePositionPercent, operationalCommand.equipmentPower)
        case let .enemy(enemyCommand):
            return (enemyCommand.fanSpeedPercent, enemyCommand.valvePositionPercent, enemyCommand.equipmentPower)
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

    // Reads last accepted request ID used for strict sequence enforcement.
    private func loadLastRequestId() -> Int? {
        guard let value = userDefaults.object(forKey: lastRequestIdKey) as? Int else {
            return nil
        }
        return value
    }

    // Persists most recently accepted request ID after success or explicit rejection tracking.
    private func saveLastRequestId(_ value: Int) {
        userDefaults.set(value, forKey: lastRequestIdKey)
    }

    // Persists accepted command timestamp for auditing/diagnostics.
    private func saveLastTimestamp(_ date: Date) {
        userDefaults.set(date.timeIntervalSince1970, forKey: lastTimestampKey)
    }

    // Reads most recent seen command timestamp used for monotonic and spacing checks.
    private func loadLastSeenTimestamp() -> Date? {
        guard let value = userDefaults.object(forKey: lastSeenTimestampKey) as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: value)
    }

    // Persists timestamp of any decoded request, even if later rejected, to block tight replay attempts.
    private func saveLastSeenTimestamp(_ date: Date) {
        userDefaults.set(date.timeIntervalSince1970, forKey: lastSeenTimestampKey)
    }

    // Emits detailed rejection context for security troubleshooting and demo visibility.
    private func logSecurityFailure(_ message: String) {
        print("[Gateway Security Detail] \(message)")
    }

    // Uses a fixed UTC formatter so logs are deterministic across device locales.
    private func formatTimestamp(_ date: Date) -> String {
        Self.securityTimestampFormatter.string(from: date)
    }
}
