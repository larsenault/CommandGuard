//  CommandGuardGatewayApp.swift
//  CommandGuardGateway
//
/*
This file was developed with the assistance of generative AI tools.
All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
*/

import SwiftUI

// Entry point for the macOS gateway app.
@main
struct CommandGuardGatewayApp: App {
    // In-memory inbox used for the initial UI wiring.
    private let inbox = GatewayInbox.sample()

    // Main window scene for the gateway.
    var body: some Scene {
        WindowGroup {
            ContentView(inbox: inbox)
        }
    }
}
