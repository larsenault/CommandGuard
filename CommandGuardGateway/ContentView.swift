//
//  ContentView.swift
//  CommandGuardGateway
//
//  Created by Luke Arsenault on 2/12/26.
//

import SwiftUI

// Root view that shows three primary boxes: received commands, recent commands, and digital twin.
struct ContentView: View {
    // Observable store that provides decoded commands for display.
    @StateObject private var inbox: GatewayInbox

    // Initializes the view with a provided inbox.
    init(inbox: GatewayInbox) {
        _inbox = StateObject(wrappedValue: inbox)
    }

    // Main UI layout for the macOS gateway dashboard.
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Box: received commands (parsed values).
            DashboardBox(title: "Received Commands") {
                ReceivedCommandsView(commands: inbox.commands)
            }

            // Box: recent commands (placeholder for later logic).
            DashboardBox(title: "Recent Commands") {
                PlaceholderBoxContent(text: "No recent command history yet.")
            }

            // Box: digital twin (placeholder for later integration).
            DashboardBox(title: "Digital Twin") {
                PlaceholderBoxContent(text: "Digital twin status will appear here.")
            }
        }
        .padding(16)
    }
}

// A titled container used for the three dashboard sections.
private struct DashboardBox<Content: View>: View {
    // Title displayed at the top of the box.
    let title: String
    // Box content provided by the caller.
    let content: Content

    // Initializes the box with a title and a content builder.
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    // Layout for the dashboard box.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

// Scrollable list of received command rows.
private struct ReceivedCommandsView: View {
    // Commands to render in the list.
    let commands: [CommandEnvelope]

    // Layout for the received command list.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
                    CommandRow(command: command)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// Placeholder text used for unfinished boxes.
private struct PlaceholderBoxContent: View {
    // Placeholder text to display.
    let text: String

    // Layout for placeholder content.
    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
    }
}

// Renders a single command row with metadata and parsed values.
private struct CommandRow: View {
    // The decoded command envelope to display.
    let command: CommandEnvelope

    // Layout for a single row in the command list.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Primary identifier line for quick scanning.
            Text("Request \(command.requestId) • \(command.operatorId)")
                .font(.headline)
            // Raw timestamp as provided by the envelope.
            Text(command.timestamp)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // Render parsed command body values.
            CommandValuesView(commandBody: command.command)
        }
        .padding(.vertical, 4)
    }
}

// Renders a compact list of parsed command values.
private struct CommandValuesView: View {
    // The control values contained within the command envelope.
    let commandBody: CommandBody

    // Layout for the command value summary.
    var body: some View {
        let powerText = commandBody.equipmentPower ? "On" : "Off"
        let controlText = commandBody.controlEnabled ? "Enabled" : "Disabled"

        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "Temp: %.1f°F", commandBody.temperatureSetpointF))
            Text(String(format: "Humidity: %.0f%%", commandBody.humiditySetpointPercent))
            Text(String(format: "Fan: %.0f%%", commandBody.fanSpeedPercent))
            Text(String(format: "Valve: %.0f%%", commandBody.valvePositionPercent))
            Text("Power: \(powerText)")
            Text("Control: \(controlText)")
        }
        .font(.caption)
    }
}

#Preview {
    ContentView(inbox: GatewayInbox.sample())
}
