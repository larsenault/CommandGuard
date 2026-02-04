import Foundation

struct CommandSendResult {
    let responseId: UUID
    let receivedAt: Date
}

enum CommandSendError: Error {
    case rejected(reason: String)
    case network(reason: String)
    case internalError(reason: String)

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

    var userMessage: String {
        switch self {
        case let .rejected(reason), let .network(reason), let .internalError(reason):
            return reason
        }
    }
}

struct CommandSendService {
    func send(command: CommandBody) async -> Result<CommandSendResult, CommandSendError> {
        let delayNanoseconds = UInt64(Int.random(in: 300...1200)) * 1_000_000
        do {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch {
            return .failure(.internalError(reason: "Send interrupted"))
        }

        if command.valvePositionPercent > 90 {
            return .failure(.rejected(reason: "Rejected: valve position above 90%"))
        }

        if command.equipmentPower, command.fanSpeedPercent < 5 {
            return .failure(.rejected(reason: "Rejected: fan speed too low for power ON"))
        }

        let roll = Int.random(in: 1...100)
        if roll <= 12 {
            return .failure(.network(reason: "Network timeout"))
        }
        if roll <= 18 {
            return .failure(.network(reason: "Unreachable host"))
        }

        return .success(CommandSendResult(responseId: UUID(), receivedAt: Date()))
    }
}
