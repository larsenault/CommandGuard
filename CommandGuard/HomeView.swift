//  HomeView.swift
//  CommandGuard

import SwiftUI
import Foundation

struct HomeView: View {
    @AppStorage("nextRequestId") private var nextRequestId: Int = 1001
    @AppStorage("operatorId") private var operatorId: String = "operator-1234"
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedSection: HomeSection = .build

    private static let eventTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

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
                    HStack {
                        Picker("Section", selection: $selectedSection) {
                            ForEach(HomeSection.allCases, id: \.self) { section in
                                Text(section.title)
                                    .tag(section)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(.primary)
                        .overlay {
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

                        Spacer()
                    }
                    .padding(.horizontal)

                    switch selectedSection {
                    case .build:
                        Form {
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
                                Toggle("Equipment Power", isOn: $viewModel.equipmentPower)
                                Toggle("Control Enabled", isOn: $viewModel.controlEnabled)
                            }
                            if viewModel.sendState == .sending, let statusTitle = viewModel.statusTitle {
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
                        }
                    case .recent:
                        RecentCommandsView(
                            events: viewModel.recentEvents,
                            timestampFormatter: Self.eventTimestampFormatter
                        )
                    }
                }

                if viewModel.showsResultPopup {
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
        }
    }
}

#Preview { HomeView() }
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

