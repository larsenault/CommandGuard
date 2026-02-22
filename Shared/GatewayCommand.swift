//  GatewayCommand.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import Foundation

// Lightweight model for representing a received command in the gateway UI.
struct GatewayCommand: Identifiable, Hashable {
    // Stable identifier for list selection.
    let id: UUID
    // Timestamp for when the command was received locally.
    let receivedAt: Date
    // Raw command payload (JSON string) for display or debugging.
    let commandText: String

    // Initializes a command with optional defaults for id and timestamp.
    init(id: UUID = UUID(), receivedAt: Date = Date(), commandText: String) {
        self.id = id
        self.receivedAt = receivedAt
        self.commandText = commandText
    }
}
