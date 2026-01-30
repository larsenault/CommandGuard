//  HomeView.swift
//  CommandGuard

import SwiftUI

struct HomeView: View {
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
                        print("=== SEND COMMAND TAPPED ===")
                        print("Temperature Setpoint: \(temperatureSetpoint)")
                        print("Humidity Setpoint: \(humiditySetpoint)")
                        print("Fan Speed: \(fanSpeed)")
                        print("Valve Position: \(valvePosition)")
                        print("Equipment Power: \(equipmentPower)")
                        print("Control Enabled: \(controlEnabled)")
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

