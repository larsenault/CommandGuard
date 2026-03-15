//  EnemyEmulationView.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import SwiftUI

struct EnemyEmulationView: View {
    // Shared view model from HomeView drives all form values and send state.
    @ObservedObject var viewModel: HomeViewModel
    // Next command request ID is owned by parent and incremented after successful sends.
    @Binding var nextRequestId: Int
    // Operator identifier embedded in outbound enemy-emulation commands.
    let operatorId: String
    
    // Maps high-level send state styling to concrete UI colors used across progress/popup.
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
        ZStack {
            // Primary form with all enemy-command inputs grouped by function.
            Form {
                Section("Gateway") {
                    // Gateway picker binds directly to selected gateway ID in the view model.
                    Picker("Gateway", selection: $viewModel.selectedGatewayId) {
                        Text("Select a gateway")
                            .tag(Optional<String>.none)
                        ForEach(viewModel.gateways) { gateway in
                            Text(gateway.displayName)
                                .tag(Optional(gateway.id))
                        }
                    }
                    .pickerStyle(.menu)

                    // Helpful empty-state text when Bonjour discovery has not found a target.
                    if viewModel.gateways.isEmpty {
                        Text("No gateways found on the local network.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Setpoint Injection") {
                    // Temperature payload field for malicious setpoint override testing.
                    HStack {
                        Text("Temperature (°F)")
                        Spacer()
                        TextField("Temp", value: $viewModel.enemyTemperatureSetpoint, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 100)
                    }

                    // Humidity payload field for malicious setpoint override testing.
                    HStack {
                        Text("Humidity (%)")
                        Spacer()
                        TextField("Humidity", value: $viewModel.enemyHumiditySetpoint, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 100)
                    }
                }

                Section("Actuator Injection") {
                    // Fan-speed actuator command value to emulate unauthorized manipulation.
                    HStack {
                        Text("Fan Speed (%)")
                        Spacer()
                        TextField("Fan", value: $viewModel.enemyFanSpeed, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 100)
                    }

                    // Valve-position actuator command value to emulate unauthorized manipulation.
                    HStack {
                        Text("Valve Position (%)")
                        Spacer()
                        TextField("Valve", value: $viewModel.enemyValvePosition, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 100)
                    }

                    // Boolean actuator control for full equipment power state changes.
                    Toggle("Equipment Power", isOn: $viewModel.enemyEquipmentPower)
                }

                Section("Attack Mode") {
                    // Attack mode chooses how the command is intentionally malformed or replayed.
                    Picker("Mode", selection: $viewModel.enemyAttackMode) {
                        ForEach(EnemyAttackMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    // Contextual helper text explains the selected attack strategy behavior.
                    if viewModel.enemyAttackMode == .replayNonce {
                        Text("Replay Nonce uses the most recent accepted enemy command nonce.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if viewModel.enemyAttackMode == .invalidSignature {
                        Text("Invalid Signature sends a command with a deliberately tampered signature.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                // Inline progress section shown only while a command is actively being sent.
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
                        // Send is performed asynchronously; update request ID only when send succeeds.
                        Task {
                            if let updatedRequestId = await viewModel.sendEnemyCommand(requestId: nextRequestId, operatorId: operatorId) {
                                nextRequestId = updatedRequestId
                            }
                        }
                    } label: {
                        Text(viewModel.isSending ? "Sending..." : "Send Enemy Command")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.isSending)
                    .opacity(viewModel.isSending ? 0.7 : 1)
                }
            }
            
            // Modal-style result popup overlays form after response is received.
            if viewModel.showsResultPopup {
                ZStack {
                    // Dimmed scrim to focus user attention on result details.
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            // Colored status indicator (neutral/success/failure).
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
                                // Clears popup presentation state in the shared view model.
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
        .navigationTitle("Enemy Emulation")
    }
}

#Preview {
    EnemyEmulationView(
        viewModel: HomeViewModel(),
        nextRequestId: .constant(1000),
        operatorId: "Luke-Arsenault"
    )
}
