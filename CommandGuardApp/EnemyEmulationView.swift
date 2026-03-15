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
    @ObservedObject var viewModel: HomeViewModel
    @Binding var nextRequestId: Int
    let operatorId: String

    var body: some View {
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

            Section("Setpoint Injection") {
                HStack {
                    Text("Temperature (°F)")
                    Spacer()
                    TextField("Temp", value: $viewModel.enemyTemperatureSetpoint, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                }

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
                HStack {
                    Text("Fan Speed (%)")
                    Spacer()
                    TextField("Fan", value: $viewModel.enemyFanSpeed, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                }

                HStack {
                    Text("Valve Position (%)")
                    Spacer()
                    TextField("Valve", value: $viewModel.enemyValvePosition, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                }

                Toggle("Equipment Power", isOn: $viewModel.enemyEquipmentPower)
            }

            if viewModel.sendState == .sending, let statusTitle = viewModel.statusTitle {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusTitle)
                                .font(.headline)

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
