//  CommandGuardApp.swift
//  CommandGuard
//
// This file is built automatically with any new Xcode project.

import SwiftUI
import SwiftData

@main
struct CommandGuardApp: App {
    // Shared SwiftData container for the app's persistent models.
    var sharedModelContainer: ModelContainer = {
        // Define the model schema and on-disk configuration.
        let schema = Schema([
            Item.self,
        ])
        // Use persistent storage so items survive app restarts.
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            // Initialize the container once at app launch.
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        // Root scene hosting the main HomeView.
        WindowGroup {
            HomeView()
        }
        // Inject SwiftData container into the scene environment.
        .modelContainer(sharedModelContainer)
    }
}
