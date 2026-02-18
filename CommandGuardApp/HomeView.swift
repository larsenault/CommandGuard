//  HomeView.swift
//  CommandGuard
//
//
/*
This file was developed with the assistance of generative AI tools.
All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
*/

import SwiftUI
import Foundation

struct HomeView: View {
    // Persisted user context for request sequencing and operator identity.
    @AppStorage("nextRequestId") private var nextRequestId: Int = 1000
    @AppStorage("operatorId") private var operatorId: String = "Luke-Arsenault"
    // View model drives form state, send status, and recent events.
    @StateObject private var viewModel = HomeViewModel()
    // Top-level navigation within the home screen.
    @State private var selectedSection: HomeSection = .build
    // Confirmation state for resetting request id and history.
    @State private var showsResetConfirmation: Bool = false

    // Shared formatter for the recent-events list (ISO 8601).
    private static let eventTimestampFormatter: (Date) -> String = { date in
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    // Maps the current send status to a UI color.
    private var statusColor: Color {
        switch viewModel.statusStyle {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 8) {
                    // Section picker for switching between build and recent views.
                    HStack {
                        Picker(selection: $selectedSection) {
                            ForEach(HomeSection.allCases, id: \.self) { section in
                                Text(section.title)
                                    .tag(section)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedSection.title)
                                    .font(.subheadline.weight(.semibold))
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                        }
                        .pickerStyle(.menu)
                        .tint(.primary)

                        Spacer()
                    }
                    .padding(.horizontal)

                    switch selectedSection {
                    case .build:
                        // Form for building and sending a command.
                        Form {
                            Section("Gateway") {
                                Picker("Gateway", selection: $viewModel.selectedGatewayId) {
                                    Text("Select a gateway")
                                        .tag(Optional<String>.none)
                                    ForEach(viewModel.gateways) { gateway in
                                        Text(gateway.displayName)
                                            .tag(Optional(gateway.id))
                                    }
                                }
                                .pickerStyle(.menu)

                                if viewModel.gateways.isEmpty {
                                    Text("No gateways found on the local network.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Section("Temperature Setpoint (°F)") {
                                HStack {
                                    Slider(value: $viewModel.temperatureSetpoint, in: 59...86, step: 0.1)
                                    Text(String(format: "%.1f", viewModel.temperatureSetpoint))
                                        .frame(width: 50, alignment: .trailing)
                                }
                            }
                            Section("Humidity Setpoint (%)") {
                                HStack {
                                    Slider(value: $viewModel.humiditySetpoint, in: 20...60, step: 0.1)
                                    Text(String(format: "%.1f", viewModel.humiditySetpoint))
                                        .frame(width: 50, alignment: .trailing)
                                }
                            }
                            Section("Fan Speed (%)") {
                                HStack {
                                    Slider(value: $viewModel.fanSpeed, in: 0...100, step: 1)
                                    Text("\(Int(viewModel.fanSpeed))")
                                        .frame(width: 50, alignment: .trailing)
                                }
                            }
                            Section("Valve Position (%)") {
                                HStack {
                                    Slider(value: $viewModel.valvePosition, in: 0...100, step: 1)
                                    Text("\(Int(viewModel.valvePosition))")
                                        .frame(width: 50, alignment: .trailing)
                                }
                            }
                            Section {
                                // Binary command flags.
                                Toggle("Equipment Power", isOn: $viewModel.equipmentPower)
                                Toggle("Control Enabled", isOn: $viewModel.controlEnabled)
                            }
                            if viewModel.sendState == .sending, let statusTitle = viewModel.statusTitle {
                                // Inline status while the command is being sent.
                                Section {
                                    HStack(alignment: .top, spacing: 12) {
                                        ProgressView()
                                            .tint(statusColor)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(statusTitle)
                                                .font(.headline)
                                                .foregroundStyle(statusColor)

                                            if let statusMessage = viewModel.statusMessage {
                                                Text(statusMessage)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            Section {
                                // Triggers the send operation and updates the request id on success.
                                Button {
                                    Task {
                                        if let updatedRequestId = await viewModel.sendCommand(requestId: nextRequestId, operatorId: operatorId) {
                                            nextRequestId = updatedRequestId
                                        }
                                    }
                                } label: {
                                    Text(viewModel.isSending ? "Sending..." : "Send Command")
                                        .frame(maxWidth: .infinity)
                                }
                                .disabled(viewModel.isSending)
                                .opacity(viewModel.isSending ? 0.7 : 1)
                            }
                            Section {
                                Button {
                                    showsResetConfirmation = true
                                } label: {
                                    Text("Reset Request ID")
                                        .frame(maxWidth: .infinity)
                                }
                                .disabled(viewModel.isSending)
                            }
                        }
                        .alert("Reset Request ID?", isPresented: $showsResetConfirmation) {
                            Button("Reset and Clear History", role: .destructive) {
                                nextRequestId = 1000
                                viewModel.clearRecentEvents()
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("This resets the request sequence to 1000 and clears recent commands.")
                        }
                    case .recent:
                        // Read-only timeline of recently sent commands.
                        RecentCommandsView(
                            events: viewModel.recentEvents,
                            timestampFormatter: Self.eventTimestampFormatter
                        )
                    }
                }

                if viewModel.showsResultPopup {
                    // Modal-style overlay for final send result.
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()

                        VStack(spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 12, height: 12)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    if let statusTitle = viewModel.statusTitle {
                                        Text(statusTitle)
                                            .font(.headline)
                                            .foregroundStyle(statusColor)
                                    }

                                    if let statusMessage = viewModel.statusMessage {
                                        Text(statusMessage)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Button("Dismiss") {
                                    viewModel.dismissPopup()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: 320)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(radius: 20)
                        .padding(24)
                    }
                }
            }
            .navigationTitle("Datacenter Cooling")
            .onAppear {
                viewModel.startBrowsing()
            }
            .onDisappear {
                viewModel.stopBrowsing()
            }
        }
    }
}

#Preview { HomeView() }
// Top-level sections available in the HomeView picker.
enum HomeSection: CaseIterable {
    case build
    case recent

    var title: String {
        switch self {
        case .build:
            return "Build Command"
        case .recent:
            return "Recent Commands"
        }
    }
}
