//  DigitalTwinModel.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/
//  Shared physical-system model definitions for the datacenter cooling twin.

import Foundation

// Represents the continuous state of the modeled room at a point in time.
public struct DigitalTwinState: Equatable, Codable {
    public let temperatureF: Double
    public let humidityPercent: Double

    public init(temperatureF: Double, humidityPercent: Double) {
        self.temperatureF = temperatureF
        self.humidityPercent = humidityPercent
    }

    // Initial state from the physical system design.
    public static let initial = DigitalTwinState(
        temperatureF: 72.0,
        humidityPercent: 45.0
    )
}

// Encapsulates model parameters and policy constraints for the digital twin.
public enum DigitalTwinModel {
    // Fixed simulation timestep.
    public static let dtSeconds: Double = 5.0

    // Ambient reference conditions.
    public static let ambientTemperatureF: Double = 72.0
    public static let ambientHumidityPercent: Double = 45.0

    // Temperature dynamics coefficients (heat gain rate and cooling rate).
    public static let qLoad: Double = 0.02
    public static let qCool: Double = 0.04
    public static let qDrift: Double = 0.0005

    // Humidity dynamics coefficients (humidity gain rate and dehumidification rate).
    public static let hLoad: Double = 0.004
    public static let hDehum: Double = 0.01
    public static let hDrift: Double = 0.0005

    // Safe operating bounds from the physical system design.
    public static let safeTemperatureRangeF: ClosedRange<Double> = 59.0...89.6
    public static let safeHumidityRangePercent: ClosedRange<Double> = 8.0...80.0

    // Physical humidity limits used by the model clamp.
    public static let physicalHumidityRangePercent: ClosedRange<Double> = 0.0...100.0

    // Command policy constraints.
    public static let fanRangeWhenPowerOnPercent: ClosedRange<Double> = 30.0...100.0
    public static let valveRangeWhenPowerOnPercent: ClosedRange<Double> = 20.0...100.0
    public static let fanRequiredWhenPowerOffPercent: Double = 0.0
    public static let valveRequiredWhenPowerOffPercent: Double = 0.0

    // Applies one discrete-time model update using the current state and command input.
    public static func step(state: DigitalTwinState, command: CommandBody) -> DigitalTwinState {
        let fanNormalized = normalizePercent(command.fanSpeedPercent) // (F)
        let valveNormalized = normalizePercent(command.valvePositionPercent) // (V)
        let powerDisturbance = command.equipmentPower ? 1.0 : 0.0 // (P)

        let nextTemperature = state.temperatureF + dtSeconds * (
            qLoad * powerDisturbance
            - qCool * (fanNormalized * valveNormalized)
            + qDrift * (ambientTemperatureF - state.temperatureF)
        )

        let nextHumidityRaw = state.humidityPercent + dtSeconds * (
            hLoad * powerDisturbance
            - hDehum * (fanNormalized * valveNormalized)
            + hDrift * (ambientHumidityPercent - state.humidityPercent)
        )
        let nextHumidity = clamp(nextHumidityRaw, to: physicalHumidityRangePercent)

        return DigitalTwinState(
            temperatureF: nextTemperature,
            humidityPercent: nextHumidity
        )
    }

    // Simulates forward for a time horizon and returns each resulting state step.
    public static func simulate(
        state initialState: DigitalTwinState,
        command: CommandBody,
        seconds: Double
    ) -> [DigitalTwinState] {
        // If the requested horizon is zero or negative, there is nothing to predict.
        guard seconds > 0 else {
            return []
        }

        // Convert real time (seconds) into the number of full model updates to run.
        // Round down so we only simulate complete dt-sized steps.
        let stepCount = Int((seconds / dtSeconds).rounded(.down))

        // If the horizon is smaller than one dt step, return no forecast states.
        guard stepCount > 0 else {
            return []
        }

        // This will hold the predicted future room states (T/H values).
        var states: [DigitalTwinState] = []
        states.reserveCapacity(stepCount)

        // Start from the current known state and move forward one step at a time.
        var current = initialState
        for _ in 0..<stepCount {
            // Apply one physics update using the same command each step.
            let next = step(state: current, command: command)

            // Save the predicted state so callers can inspect the full trajectory.
            states.append(next)

            // Make this state the new baseline for the next loop iteration.
            current = next
        }

        // Return all predicted future states (not including the initial input state).
        return states
    }

    private static func normalizePercent(_ value: Double) -> Double {
        value / 100.0
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
