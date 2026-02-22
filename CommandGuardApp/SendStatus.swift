//  SendStatus.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import Foundation

enum SendState: Equatable {
    case idle
    case sending
    case success
    case failure(message: String?)

    var statusText: String? {
        switch self {
        case .idle:
            return nil
        case .sending:
            return "Sending..."
        case .success:
            return "Success"
        case let .failure(message):
            return message ?? "Failure"
        }
    }

    var showsSpinner: Bool {
        if case .sending = self {
            return true
        }
        return false
    }

    var isSendDisabled: Bool {
        if case .sending = self {
            return true
        }
        return false
    }

    var statusStyle: StatusStyle {
        switch self {
        case .idle, .sending:
            return .neutral
        case .success:
            return .success
        case .failure:
            return .failure
        }
    }

    var detailsMessage: String? {
        if case let .failure(message) = self {
            return message
        }
        return nil
    }
}

enum StatusStyle {
    case neutral
    case success
    case failure
}
