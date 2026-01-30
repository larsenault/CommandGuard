//  HomeView.swift
//  CommandGuard

import SwiftUI
import Foundation

struct HomeView: View {
    @AppStorage("nextRequestId") private var nextRequestId: Int = 1001
    @AppStorage("operatorId") private var operatorId: String = "operator-1234"
    @State private var temperatureSetpoint: Double = 22
    @State private var humiditySetpoint: Double = 40
    @State private var fanSpeed: Double = 50
    @State private var valvePosition: Double = 50
    @State private var equipmentPower: Bool = false
    @State private var controlEnabled: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Temperature Setpoint (°F)") {
                    HStack {
                        Slider(value: $temperatureSetpoint, in: 59...86, step: 0.1)
                        Text(String(format: "%.1f", temperatureSetpoint))
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                Section("Humidity Setpoint (%)") {
                    HStack {
                        Slider(value: $humiditySetpoint, in: 20...60, step: 0.1)
                        Text(String(format: "%.1f", humiditySetpoint))
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                Section("Fan Speed (%)") {
                    HStack {
                        Slider(value: $fanSpeed, in: 0...100, step: 1)
                        Text("\(Int(fanSpeed))")
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                Section("Valve Position (%)") {
                    HStack {
                        Slider(value: $valvePosition, in: 0...100, step: 1)
                        Text("\(Int(valvePosition))")
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                Section {
                    Toggle("Equipment Power", isOn: $equipmentPower)
                    Toggle("Control Enabled", isOn: $controlEnabled)
                }
                Section {
                    Button {
                        // Build command body from current UI state
                        let body = CommandBody(
                            temperatureSetpointF: temperatureSetpoint,
                            humiditySetpointPercent: humiditySetpoint,
                            fanSpeedPercent: fanSpeed,
                            valvePositionPercent: valvePosition,
                            equipmentPower: equipmentPower,
                            controlEnabled: controlEnabled
                        )

                        // Create envelope with timestamp and sequential requestId
                        let envelope = CommandEnvelope(
                            timestamp: iso8601Now(),
                            requestId: nextRequestId,
                            operatorId: operatorId,
                            command: body
                        )

                        // Serialize to JSON and print for verification
                        do {
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            let data = try encoder.encode(envelope)
                            if let jsonString = String(data: data, encoding: .utf8) {
                                print("=== SEND COMMAND JSON ===\n\(jsonString)")
                            }
                        } catch {
                            print("Failed to encode command: \(error)")
                        }

                        // Increment request id for next command
                        nextRequestId += 1
                    } label: {
                        Text("Send Command")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Datacenter Cooling")
        }
    }
}

#Preview { HomeView() }

