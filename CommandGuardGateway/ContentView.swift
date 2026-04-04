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
    // MARK: - Dependencies
    // Observable store that provides decoded commands for display.
    @ObservedObject private var inbox: GatewayInbox
    // Observable listener that manages the network state.
    @ObservedObject private var listener: GatewayListener

    // MARK: - Initialization
    // Initializes the view with a provided inbox and listener.
    init(inbox: GatewayInbox, listener: GatewayListener) {
        _inbox = ObservedObject(wrappedValue: inbox)
        _listener = ObservedObject(wrappedValue: listener)
    }

    // MARK: - View
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

                // Box: digital twin (current state + last prediction result).
                DashboardBox(title: "Digital Twin:") {
                    DigitalTwinStatusView(status: inbox.twinStatus)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Derived UI State
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
    // MARK: - Inputs
    // Title displayed at the top of the box.
    let title: String
    // Box content provided by the caller.
    let content: Content

    // MARK: - Initialization
    // Initializes the box with a title and a content builder.
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    // MARK: - View
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
    // MARK: - Inputs
    // Latest command to render (if available).
    let command: GatewayInbox.ReceivedCommand?

    // MARK: - View
    // Renders either the latest command row or an empty-state placeholder.
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
    // MARK: - Inputs
    // Commands to render in the list.
    let records: [GatewayInbox.CommandRecord]

    // MARK: - View
    // Displays a placeholder when empty, otherwise a vertical scroll list of command attempts.
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
    // MARK: - Inputs
    // Historical command attempt and its acceptance/rejection metadata.
    let record: GatewayInbox.CommandRecord

    // MARK: - View
    // Shows attempt outcome first, then the normalized command details.
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
            CommandRow(command: record.command)
        }
    }
}

// Shows current twin state and latest prediction horizon summary.
private struct DigitalTwinStatusView: View {
    // MARK: - Inputs
    // Most recent twin snapshot emitted by the gateway validation pipeline.
    let status: GatewayInbox.TwinStatus?

    // MARK: - Formatting
    // Formats the "Updated" timestamp in local time for operator readability.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    // MARK: - View
    // Presents live state, forecast safety, and end-of-horizon values.
    var body: some View {
        guard let status else {
            return AnyView(PlaceholderBoxContent(text: "No digital twin data yet."))
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.currentStateSafe ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(status.currentStateSafe ? "Current state: Safe" : "Current state: Unsafe")
                        .font(.caption.weight(.semibold))
                }

                Text(String(format: "Current Temp: %.2f°F", status.currentState.temperatureF))
                Text(String(format: "Current Humidity: %.2f%%", status.currentState.humidityPercent))

                Divider()

                HStack(spacing: 6) {
                    Circle()
                        .fill(status.forecastSafe ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(status.forecastSafe ? "Forecast: Safe" : "Forecast: Unsafe")
                        .font(.caption.weight(.semibold))
                }
                Text(String(format: "Horizon: %.0f seconds", status.forecastHorizonSeconds))
                Text(String(format: "Forecast Temp @ End: %.2f°F", status.forecastEndState.temperatureF))
                Text(String(format: "Forecast Humidity @ End: %.2f%%", status.forecastEndState.humidityPercent))

                Divider()

                Text("Updated: \(Self.timestampFormatter.string(from: status.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        )
    }
}

// Placeholder text used for unfinished boxes.
private struct PlaceholderBoxContent: View {
    // MARK: - Inputs
    // Placeholder text to display.
    let text: String

    // MARK: - View
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
    // MARK: - Inputs
    // The decoded command envelope to display.
    let command: GatewayInbox.ReceivedCommand

    // MARK: - View
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
            Text("Intent: \(command.intent == .enemyEmulation ? "Enemy Emulation" : "Operational")")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Render parsed command body values.
            CommandValuesView(payload: command.payload)
            ModbusTCPFramesView(frames: command.modbusTCPFrames)
        }
        .padding(.vertical, 4)
    }
}

// Renders a compact list of parsed command values.
private struct CommandValuesView: View {
    // MARK: - Inputs
    // The control values contained within the command.
    let payload: GatewayInbox.CommandPayload

    // MARK: - View
    // Layout for the command value summary.
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch payload {
            case let .operational(commandBody):
                let powerText = commandBody.equipmentPower ? "On" : "Off"
                let emulationText = commandBody.enemyEmulation ? "On" : "Off"
                Text(String(format: "Fan: %.0f%%", commandBody.fanSpeedPercent))
                Text(String(format: "Valve: %.0f%%", commandBody.valvePositionPercent))
                Text("Power: \(powerText)")
                Text("Enemy Emulation: \(emulationText)")
            case let .enemy(commandBody):
                let powerText = commandBody.equipmentPower ? "On" : "Off"
                Text(String(format: "Temp: %.1f°F", commandBody.temperatureSetpointF))
                Text(String(format: "Humidity: %.0f%%", commandBody.humiditySetpointPercent))
                Text(String(format: "Fan: %.1f%%", commandBody.fanSpeedPercent))
                Text(String(format: "Valve: %.1f%%", commandBody.valvePositionPercent))
                Text("Power: \(powerText)")
            }
        }
        .font(.caption)
    }
}

// Renders the Modbus TCP frames generated from a command when available.
private struct ModbusTCPFramesView: View {
    // MARK: - Inputs
    // Optional Modbus TCP frame metadata attached to the command.
    let frames: GatewayInbox.ModbusTCPFrames?

    // MARK: - View
    // Displays register and power write frames with transaction IDs and hex payloads.
    var body: some View {
        Group {
            if let frames {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modbus TCP:")
                        .font(.caption.weight(.semibold))
                    Text("Registers (TX \(frames.registerTransactionId)): \(frames.registerFrameHex)")
                    Text("Power (TX \(frames.powerTransactionId)): \(frames.powerFrameHex)")
                }
                .font(.caption.monospaced())
                .padding(.top, 2)
            }
        }
    }
}

#Preview {
    let inbox = GatewayInbox.sample()
    let listener = GatewayListener(inbox: inbox)
    return ContentView(inbox: inbox, listener: listener)
}
