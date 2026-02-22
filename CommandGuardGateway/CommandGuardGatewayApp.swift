//  CommandGuardGatewayApp.swift
//  CommandGuardGateway
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import SwiftUI

// Entry point for the macOS gateway app.
@main
struct CommandGuardGatewayApp: App {
    // In-memory inbox used for live command ingestion.
    private let inbox: GatewayInbox
    // Listener responsible for accepting incoming network commands.
    private let listener: GatewayListener

    // Creates the inbox and listener once for the app lifecycle.
    init() {
        let inbox = GatewayInbox()
        self.inbox = inbox
        self.listener = GatewayListener(inbox: inbox)
    }

    // Main window scene for the gateway.
    var body: some Scene {
        WindowGroup {
            ContentView(inbox: inbox, listener: listener)
                // Start listening as soon as the main window appears.
                .onAppear {
                    listener.start()
                }
        }
    }
}
