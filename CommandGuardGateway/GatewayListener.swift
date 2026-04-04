//  GatewayListener.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import Combine
import CryptoKit
import Foundation
import Network

// Listens for incoming NDJSON command envelopes over TCP and responds with NDJSON status.
final class GatewayListener: ObservableObject {
    // MARK: - State
    // High-level listener lifecycle state for UI or logging.
    enum State: Equatable {
        case idle
        case starting
        case ready(port: UInt16)
        case failed(message: String)
        case stopped
    }

    // Published state so SwiftUI can reflect listener status.
    @Published private(set) var state: State = .idle

    // MARK: - Dependencies
    // Inbox that stores decoded commands for display in the gateway UI.
    private let inbox: GatewayInbox
    // Dedicated queue for Network framework callbacks.
    private let queue = DispatchQueue(label: "CommandGuard.GatewayListener")
    // Signature verifier used to validate incoming command envelopes.
    private let verifier: GatewaySignatureVerifier
    // Command validator enforcing schema, sequencing, and replay rules.
    private let commandValidator: GatewayCommandValidator
    // Active TCP listener instance (nil when stopped).
    private var listener: NWListener?
    // Periodic task that advances the twin rollout every 5 seconds.
    private var heartbeatTask: Task<Void, Never>?

    // MARK: - Initialization
    // Initialize the listener with a shared inbox and signature verifier.
    init(inbox: GatewayInbox, verifier: GatewaySignatureVerifier = GatewaySignatureVerifier()) {
        self.inbox = inbox
        self.verifier = verifier
        self.commandValidator = GatewayCommandValidator()
    }

    // MARK: - Public API
    // Starts listening and advertising a Bonjour service for discovery.
    func start() {
        guard listener == nil else { return }
        updateState(.starting)
        startHeartbeatLoop()
        Task { [weak self] in
            guard let self else { return }
            self.commandValidator.resetTwinState()
            await self.initializeTwinStatus()
        }
        do {
            let listener = try NWListener(using: .tcp)
            // Advertise the service using the same type the app browses for.
            listener.service = NWListener.Service(name: "CommandGuard Gateway", type: "_commandguard._tcp")
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            updateState(.failed(message: error.localizedDescription))
        }
    }

    // Stops the listener and releases resources.
    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        listener?.cancel()
        listener = nil
        updateState(.stopped)
    }

    // Resets validation state (request id, timestamps, nonces) for testing.
    func resetValidationState() {
        Task {
            commandValidator.resetState()
            await MainActor.run {
                inbox.clearHistory()
            }
            await initializeTwinStatus()
        }
    }

    // MARK: - Listener Event Handling
    // Translates Network framework state changes into our simplified state.
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            // Surface the actual port assigned by the system for UI display.
            let portValue = listener?.port?.rawValue ?? 0
            updateState(.ready(port: portValue))
        case let .failed(error):
            // Mark failed and stop to allow later restart attempts.
            updateState(.failed(message: error.localizedDescription))
            stop()
        case .cancelled:
            updateState(.stopped)
        default:
            break
        }
    }

    // Configures a new connection and waits for it to become ready.
    private func handleNewConnection(_ connection: NWConnection) {
        // Keep per-connection state updates isolated from listener state.
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveCommand(from: connection)
            case .failed:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    // Receives one NDJSON command, validates it, stores it, and replies.
    private func receiveCommand(from connection: NWConnection) {
        Task.detached { [weak self] in
            guard let self else { return }
            var payload: Data?
            do {
                payload = try await self.receiveNDJSONLine(from: connection)
                guard let payload else {
                    throw NSError(
                        domain: "CommandGuard.GatewayListener",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Empty command payload"]
                    )
                }
                // Decode + validate schema/state before signature verification.
                let validationOutcome = try await self.commandValidator.decodeAndValidate(payload: payload, now: Date())
                let envelope = validationOutcome.envelope

                // Verify signature before showing the command.
                try await MainActor.run {
                    try self.verifySignature(for: envelope)
                }
                let acceptedTwinState = await self.commandValidator.acceptValidatedCommand(validationOutcome, now: Date())
                let modbusTCPFrames = self.makeModbusTCPFrames(from: envelope)
                await MainActor.run {
                    // Only append after all validation and verification succeed.
                    self.inbox.appendAccepted(
                        command: self.makeReceivedCommand(from: envelope, modbusTCPFrames: modbusTCPFrames)
                    )
                    self.inbox.updateTwinStatus(
                        currentState: acceptedTwinState,
                        predictedStates: validationOutcome.predictedStates,
                        horizonSeconds: validationOutcome.predictionHorizonSeconds
                    )
                }
                let successTimestamp = await MainActor.run { iso8601Now() }
                let responseRequestId = await MainActor.run { envelope.requestId }
                let response = GatewayResponse(
                    id: responseRequestId,
                    deliveryStatus: .delivered,
                    executionStatus: .succeeded,
                    message: "Accepted",
                    timestamp: successTimestamp
                )
                try await self.sendResponse(response, over: connection)
            } catch {
                var rejectedRequestId: Int? = nil
                if let payload {
                    if let command = await MainActor.run(body: { self.decodeReceivedCommand(from: payload) }) {
                        rejectedRequestId = command.requestId
                        await MainActor.run {
                            self.inbox.appendRejected(command: command, message: error.localizedDescription)
                        }
                        await self.commandValidator.recordRejectedRequestId(command.requestId)
                    }
                }
                Self.logSecurityFailureIfNeeded(error, requestId: rejectedRequestId)
                // Report failure to the sender while keeping the gateway alive.
                let failureTimestamp = await MainActor.run { iso8601Now() }
                let response = GatewayResponse(
                    id: rejectedRequestId ?? -1,
                    deliveryStatus: .failed,
                    executionStatus: .failed,
                    message: "Rejected: \(Self.userFacingRejectionMessage(for: error))",
                    timestamp: failureTimestamp
                )
                try? await self.sendResponse(response, over: connection)
            }
            connection.cancel()
        }
    }

    // MARK: - Transport
    // Reads from the TCP connection until a newline-delimited JSON payload is complete.
    private func receiveNDJSONLine(from connection: NWConnection) async throws -> Data {
        var buffer = Data()
        while true {
            let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let data {
                        continuation.resume(returning: data)
                        return
                    }
                    if isComplete {
                        let closeError = NSError(
                            domain: "CommandGuard.GatewayListener",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Connection closed"]
                        )
                        continuation.resume(throwing: closeError)
                        return
                    }
                    continuation.resume(returning: Data())
                }
            }
            buffer.append(chunk)
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newlineIndex]
                return Data(line)
            }
        }
    }

    // Encodes a response and sends it as NDJSON back over the connection.
    private func sendResponse(_ response: GatewayResponse, over connection: NWConnection) async throws {
        let encoder = JSONEncoder()
        var payload = try encoder.encode(response)
        payload.append(0x0A)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    // Updates the published state on the main actor.
    private func updateState(_ newState: State) {
        Task { @MainActor in
            self.state = newState
        }
    }

    // Starts (or restarts) the 5-second heartbeat that applies one predicted twin step at a time.
    private func startHeartbeatLoop() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }

                if let progress = self.commandValidator.advanceHeartbeat() {
                    await MainActor.run {
                        self.inbox.updateTwinStatus(
                            currentState: progress.currentState,
                            predictedStates: progress.predictedStates,
                            horizonSeconds: progress.horizonSeconds
                        )
                    }
                }
            }
        }
    }

    // Pulls the validator's current twin progress snapshot and publishes it to the dashboard.
    private func initializeTwinStatus() async {
        let progress = await commandValidator.currentTwinProgress()
        await MainActor.run {
            inbox.updateTwinStatus(
                currentState: progress.currentState,
                predictedStates: progress.predictedStates,
                horizonSeconds: progress.horizonSeconds
            )
        }
    }

    // Delegates signature verification to the correct verifier path for typed envelopes.
    private func verifySignature(for envelope: GatewayCommandValidator.ValidatedEnvelope) throws {
        switch envelope {
        case let .operational(operationalEnvelope):
            try verifier.verifyTyped(envelope: operationalEnvelope)
        case let .enemy(enemyEnvelope):
            try verifier.verifyTyped(envelope: enemyEnvelope)
        }
    }

    // Converts a validated envelope into the UI-friendly inbox model used across dashboard views.
    private func makeReceivedCommand(
        from envelope: GatewayCommandValidator.ValidatedEnvelope,
        modbusTCPFrames: GatewayInbox.ModbusTCPFrames? = nil
    ) -> GatewayInbox.ReceivedCommand {
        switch envelope {
        case let .operational(operationalEnvelope):
            return GatewayInbox.ReceivedCommand(
                timestamp: operationalEnvelope.timestamp,
                requestId: operationalEnvelope.requestId,
                operatorId: operationalEnvelope.operatorId,
                intent: .operational,
                payload: .operational(operationalEnvelope.command),
                modbusTCPFrames: modbusTCPFrames
            )
        case let .enemy(enemyEnvelope):
            return GatewayInbox.ReceivedCommand(
                timestamp: enemyEnvelope.timestamp,
                requestId: enemyEnvelope.requestId,
                operatorId: enemyEnvelope.operatorId,
                intent: .enemyEmulation,
                payload: .enemy(enemyEnvelope.command),
                modbusTCPFrames: modbusTCPFrames
            )
        }
    }

    // Builds Modbus TCP frame metadata for accepted operational and enemy commands.
    private func makeModbusTCPFrames(
        from envelope: GatewayCommandValidator.ValidatedEnvelope
    ) -> GatewayInbox.ModbusTCPFrames? {
        let encodedFrames: ModbusTCPEncoder.EncodedOperationalFrames
        switch envelope {
        case let .operational(operationalEnvelope):
            encodedFrames = ModbusTCPEncoder.encodeOperational(operationalEnvelope.command)
        case let .enemy(enemyEnvelope):
            encodedFrames = ModbusTCPEncoder.encodeEnemy(enemyEnvelope.command)
        }

        return GatewayInbox.ModbusTCPFrames(
            registerTransactionId: encodedFrames.registerFrame.transactionId,
            registerFrameHex: encodedFrames.registerFrame.hexString,
            powerTransactionId: encodedFrames.powerFrame.transactionId,
            powerFrameHex: encodedFrames.powerFrame.hexString
        )
    }

    // Best-effort payload decode used on failures so rejected attempts can still appear in history.
    private func decodeReceivedCommand(from payload: Data) -> GatewayInbox.ReceivedCommand? {
        let decoder = JSONDecoder()

        if let operational = try? decoder.decode(TypedCommandEnvelope<OperationalCommandBody>.self, from: payload) {
            return GatewayInbox.ReceivedCommand(
                timestamp: operational.timestamp,
                requestId: operational.requestId,
                operatorId: operational.operatorId,
                intent: .operational,
                payload: .operational(operational.command)
            )
        }

        if let enemy = try? decoder.decode(TypedCommandEnvelope<EnemyCommandBody>.self, from: payload) {
            return GatewayInbox.ReceivedCommand(
                timestamp: enemy.timestamp,
                requestId: enemy.requestId,
                operatorId: enemy.operatorId,
                intent: .enemyEmulation,
                payload: .enemy(enemy.command)
            )
        }

        return nil
    }

    // Maps internal verification/schema errors into concise messages suitable for sender-facing responses.
    private nonisolated static func userFacingRejectionMessage(for error: Error) -> String {
        if let verificationError = error as? GatewaySignatureVerifier.VerificationError {
            switch verificationError {
            case .missingSignature:
                return "Missing signature."
            case let .unsupportedAlgorithm(algorithm):
                return "Unsupported alg \(algorithm)."
            case let .unknownKeyId(keyId):
                return "Unknown keyId \(keyId)."
            case .invalidPublicKey:
                return "Invalid signing key."
            case .invalidSignature:
                return "Signature check failed."
            }
        }

        if let schemaError = error as? CommandSchemaError,
           let description = schemaError.errorDescription {
            return description
        }

        let rawMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawMessage.isEmpty {
            return "Request validation failed."
        }
        return rawMessage
    }

    // Emits security-specific logs only for replay/signature/sequencing classes of rejection.
    private nonisolated static func logSecurityFailureIfNeeded(_ error: Error, requestId: Int?) {
        let requestLabel = requestId.map(String.init) ?? "unknown"

        if let verificationError = error as? GatewaySignatureVerifier.VerificationError {
            let reason: String
            switch verificationError {
            case .missingSignature:
                reason = "missing signature"
            case let .unsupportedAlgorithm(algorithm):
                reason = "unsupported algorithm (\(algorithm))"
            case let .unknownKeyId(keyId):
                reason = "unknown keyId (\(keyId))"
            case .invalidPublicKey:
                reason = "invalid public key"
            case .invalidSignature:
                reason = "invalid signature value"
            }
            print("[Gateway Security] Rejected request \(requestLabel): signature verification failed (\(reason)).")
            return
        }

        guard let schemaError = error as? CommandSchemaError else {
            return
        }

        switch schemaError {
        case .nonceReused:
            print("[Gateway Security] Rejected request \(requestLabel): nonce replay detected.")
        case .timestampNotMonotonic:
            print("[Gateway Security] Rejected request \(requestLabel): timestamp replay/non-monotonic.")
        case .timestampTooSoon:
            print("[Gateway Security] Rejected request \(requestLabel): timestamp spacing violation.")
        case .invalidRequestId:
            print("[Gateway Security] Rejected request \(requestLabel): invalid request id.")
        case let .requestIdOutOfSequence(expected):
            print("[Gateway Security] Rejected request \(requestLabel): request id out of sequence (expected \(expected)).")
        default:
            break
        }
    }
}
