//  CommandSendService.swift
//  CommandGuard
//
/*
This file was developed with the assistance of generative AI tools.
All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
*/

import Foundation
import Network

// Represents a successful response from the gateway after a command is sent.
struct CommandSendResult {
    // Request id echoed back by the gateway for correlation.
    let requestId: Int
    // Delivery status (gateway received the command or not).
    let deliveryStatus: DeliveryStatus
    // Execution status (command succeeded or failed).
    let executionStatus: ExecutionStatus
    // Optional message from the gateway.
    let message: String?
    // Timestamp parsed from the gateway response (if provided).
    let gatewayTimestamp: Date?
    // Timestamp indicating when the response was received locally.
    let receivedAt: Date
    
    // Defines all possible errors that can occur when sending a command.
    enum CommandSendError: Error {
        case network(reason: String)
        case internalError(reason: String)
        
        // Title for displaying in the UI (e.g., alert header).
        var userTitle: String {
            switch self {
            case .network:
                return "Network Error"
            case .internalError:
                return "Error"
            }
        }
        
        // Detailed message explaining what went wrong.
        var userMessage: String {
            switch self {
            case let .network(reason), let .internalError(reason):
                return reason
            }
        }
    }
    
    // Service responsible for sending commands to the (simulated) gateway.
    struct CommandSendService {
        // Sends a signed command envelope over TCP and waits for an NDJSON response.
        func send(
            signedEnvelopeData: Data,
            command: CommandBody,
            gateway: GatewayService
        ) async -> Result<CommandSendResult, CommandSendError> {
            // Always send to the gateway; validation happens server-side.
            do {
                let response = try await sendAndReceiveNDJSON(
                    signedEnvelopeData: signedEnvelopeData,
                    gateway: gateway
                )
                let receivedAt = Date()
                // Parse the gateway timestamp if it is a valid ISO 8601 string.
                let gatewayTimestamp = parseGatewayTimestamp(response.timestamp)
                return .success(
                    CommandSendResult(
                        requestId: response.id,
                        deliveryStatus: response.deliveryStatus,
                        executionStatus: response.executionStatus,
                        message: response.message,
                        gatewayTimestamp: gatewayTimestamp,
                        receivedAt: receivedAt
                    )
                )
            } catch let error as CommandSendError {
                return .failure(error)
            } catch {
                return .failure(.internalError(reason: "Unexpected send error"))
            }
        }

        // Parses the gateway-provided timestamp string into a Date when possible.
        private func parseGatewayTimestamp(_ timestamp: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
        }

        // Creates a TCP connection, sends NDJSON, and waits for a single NDJSON response.
        private func sendAndReceiveNDJSON(
            signedEnvelopeData: Data,
            gateway: GatewayService
        ) async throws -> GatewayResponse {
            let connection = NWConnection(to: gateway.endpoint, using: .tcp)
            let queue = DispatchQueue(label: "CommandGuard.SendConnection")
            // Always cancel the connection when we finish or fail.
            defer { connection.cancel() }
            // Gate to ensure the continuation resumes only once across state callbacks.
            let resumeGate = ResumeGate()

            // Wait for the TCP connection to be ready or fail.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.stateUpdateHandler = { state in
                    Task { @MainActor in
                        switch state {
                        case .ready:
                            if resumeGate.tryResume() {
                                continuation.resume()
                            }
                        case let .failed(error):
                            if resumeGate.tryResume() {
                                continuation.resume(throwing: CommandSendError.network(reason: error.localizedDescription))
                            }
                        default:
                            break
                        }
                    }
                }
                connection.start(queue: queue)
            }

            // NDJSON framing: append newline so the gateway can parse a complete message.
            var framedPayload = signedEnvelopeData
            framedPayload.append(0x0A)

            // Send the framed payload.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: framedPayload, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: CommandSendError.network(reason: error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                })
            }

            // Receive bytes until a newline is found, then decode the response JSON.
            let responseData = try await receiveNDJSONLine(from: connection)

            let decoder = JSONDecoder()
            return try decoder.decode(GatewayResponse.self, from: responseData)
        }

        // Reads from the connection until a newline-delimited JSON response is complete.
        private func receiveNDJSONLine(from connection: NWConnection) async throws -> Data {
            var buffer = Data()
            while true {
                let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                        if let error {
                            continuation.resume(throwing: CommandSendError.network(reason: error.localizedDescription))
                            return
                        }
                        if let data {
                            continuation.resume(returning: data)
                            return
                        }
                        if isComplete {
                            continuation.resume(throwing: CommandSendError.network(reason: "Connection closed"))
                            return
                        }
                        continuation.resume(returning: Data())
                    }
                }

                buffer.append(chunk)
                if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                    // Strip the newline delimiter and return the JSON payload.
                    let line = buffer[..<newlineIndex]
                    return Data(line)
                }
            }
        }
    }
}
// Thread-safe gate for resuming a continuation exactly once.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    // Returns true if the caller is the first to resume.
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if didResume {
            return false
        }
        didResume = true
        return true
    }
}
