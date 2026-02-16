//  GatewayListener.swift
//  CommandGuard
//
/*
This file was developed with the assistance of generative AI tools.
All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
*/

import Combine
import Foundation
import Network

// Listens for incoming NDJSON command envelopes over TCP and responds with NDJSON status.
final class GatewayListener: ObservableObject {
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

    // Initialize the listener with a shared inbox and signature verifier.
    init(inbox: GatewayInbox, verifier: GatewaySignatureVerifier = GatewaySignatureVerifier()) {
        self.inbox = inbox
        self.verifier = verifier
        self.commandValidator = GatewayCommandValidator()
    }

    // Starts listening and advertising a Bonjour service for discovery.
    func start() {
        guard listener == nil else { return }
        updateState(.starting)
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
        listener?.cancel()
        listener = nil
        updateState(.stopped)
    }

    // Resets validation state (request id, timestamps, nonces) for testing.
    func resetValidationState() {
        Task {
            await commandValidator.resetState()
        }
    }

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
                let envelope = try await self.commandValidator.decodeAndValidate(payload: payload, now: Date())
                // Verify signature before showing the command.
                try await MainActor.run {
                    try self.verifier.verify(envelope: envelope)
                }
                await MainActor.run {
                    // Only append after all validation and verification succeed.
                    self.inbox.appendAccepted(envelope: envelope)
                }
                let successTimestamp = await MainActor.run { iso8601Now() }
                let response = GatewayResponse(
                    id: envelope.requestId,
                    deliveryStatus: .delivered,
                    executionStatus: .succeeded,
                    message: "Accepted",
                    timestamp: successTimestamp
                )
                try await self.sendResponse(response, over: connection)
            } catch {
                if let payload {
                    let envelope = await MainActor.run {
                        try? JSONDecoder().decode(CommandEnvelope.self, from: payload)
                    }
                    if let envelope {
                        await MainActor.run {
                            self.inbox.appendRejected(envelope: envelope, message: error.localizedDescription)
                        }
                    }
                }
                // Report failure to the sender while keeping the gateway alive.
                let failureTimestamp = await MainActor.run { iso8601Now() }
                let response = GatewayResponse(
                    id: -1,
                    deliveryStatus: .failed,
                    executionStatus: .failed,
                    message: "Rejected: \(error.localizedDescription)",
                    timestamp: failureTimestamp
                )
                try? await self.sendResponse(response, over: connection)
            }
            connection.cancel()
        }
    }

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
}
