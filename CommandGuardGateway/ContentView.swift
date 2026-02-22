//  ContentView.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import SwiftUI
import Foundation

// Root view that shows three primary boxes: received commands, recent commands, and digital twin.
struct ContentView: View {
    // Observable store that provides decoded commands for display.
    @ObservedObject private var inbox: GatewayInbox
    // Observable listener that manages the network state.
    @ObservedObject private var listener: GatewayListener

    // Initializes the view with a provided inbox and listener.
    init(inbox: GatewayInbox, listener: GatewayListener) {
        _inbox = ObservedObject(wrappedValue: inbox)
        _listener = ObservedObject(wrappedValue: listener)
    }

    // Main UI layout for the macOS gateway dashboard.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Render listener status so operators can confirm the gateway is active.
            HStack {
                Text(listenerStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Reset Request ID") {
                    listener.resetValidationState()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(alignment: .top, spacing: 16) {
                // Box: received commands (latest only).
                DashboardBox(title: "Received Command:") {
                    ReceivedCommandView(command: inbox.latestCommand)
                }

                // Box: recent commands (last 10).
                DashboardBox(title: "Recent Commands:") {
                    RecentCommandsView(records: inbox.recentCommands)
                }

                // Box: digital twin (placeholder for later integration).
                DashboardBox(title: "Digital Twin:") {
                    PlaceholderBoxContent(text: "Digital twin status will appear here.")
                }
            }
        }
        .padding(16)
    }

    // Maps listener state into a concise status string for the UI.
    private var listenerStatusText: String {
        switch listener.state {
        case .idle:
            return "Listener: Idle"
        case .starting:
            return "Listener: Starting…"
        case let .ready(port):
            return "Listener: Ready on port \(port)"
        case let .failed(message):
            return "Listener: Failed (\(message))"
        case .stopped:
            return "Listener: Stopped"
        }
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
                .frame(maxWidth: .infinity, alignment: .center)

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 320, alignment: .topLeading)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

// Shows only the most recently received command.
private struct ReceivedCommandView: View {
    // Latest command to render (if available).
    let command: CommandEnvelope?

    var body: some View {
        Group {
            if let command {
                CommandRow(command: command)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PlaceholderBoxContent(text: "No commands received yet.")
            }
        }
    }
}

// Scrollable list of recent command rows (newest first).
private struct RecentCommandsView: View {
    // Commands to render in the list.
    let records: [GatewayInbox.CommandRecord]

    var body: some View {
        if records.isEmpty {
            PlaceholderBoxContent(text: "No recent command history yet.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(records) { record in
                        RecentCommandRow(record: record)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// Renders a command row with a status header for accepted/rejected attempts.
private struct RecentCommandRow: View {
    let record: GatewayInbox.CommandRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(record.status == .accepted ? "Accepted" : "Rejected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.status == .accepted ? .green : .red)
                if let message = record.message, record.status == .rejected {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            CommandRow(command: record.envelope)
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
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 4)
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
            Text("Request \(command.requestId) \(command.operatorId)")
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
    let inbox = GatewayInbox.sample()
    let listener = GatewayListener(inbox: inbox)
    return ContentView(inbox: inbox, listener: listener)
}
