//  CommandSendService.swift
//  CommandGuard
//
/*
This file was developed with the assistance of generative AI tools.
All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
*/

import Foundation

// Represents a successful response from the gateway after a command is sent.
struct CommandSendResult {
    let responseId: UUID // Unique ID returned by the gateway to identify this command/response.
    let receivedAt: Date // Timestamp indicating when the response was received.
    
    // Defines all possible errors that can occur when sending a command.
    enum CommandSendError: Error {
        case rejected(reason: String)
        case network(reason: String)
        case internalError(reason: String)
        
        // Title for displaying in the UI (e.g., alert header).
        var userTitle: String {
            switch self {
            case .rejected:
                return "Rejected"
            case .network:
                return "Network Error"
            case .internalError:
                return "Error"
            }
        }
        
        // Detailed message explaining what went wrong.
        var userMessage: String {
            switch self {
            case let .rejected(reason), let .network(reason), let .internalError(reason):
                return reason
            }
        }
    }
    
    // Service responsible for sending commands to the (simulated) gateway.
    struct CommandSendService {
        // Sends a command asynchronously and returns either a success or failure.
        func send(command: CommandBody) async -> Result<CommandSendResult, CommandSendError> {
            let delayNanoseconds = UInt64(Int.random(in: 300...1200)) * 1_000_000 // Simulate realistic network latency (300–1200 ms).
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return .failure(.internalError(reason: "Send interrupted"))
            }
            if command.valvePositionPercent > 90 {
                return .failure(.rejected(reason: "Rejected: valve position above 90%"))
            } // Reject unsafe valve positions above 90%.

            
            if command.equipmentPower, command.fanSpeedPercent < 5 {
                return .failure(.rejected(reason: "Rejected: fan speed too low for power ON"))
            } // Reject powering equipment ON if fan speed is too low.
            
            let roll = Int.random(in: 1...100) // Random roll to inject intermittent network issues.
            if roll <= 12 {
                return .failure(.network(reason: "Network timeout"))
            } // ~12% chance of timeout.

            if roll <= 18 {
                return .failure(.network(reason: "Unreachable host"))
            } // ~6% chance of unreachable host.

            // If all checks pass, return a successful response.
            return .success(CommandSendResult(responseId: UUID(), receivedAt: Date()))
        }
    }
}
