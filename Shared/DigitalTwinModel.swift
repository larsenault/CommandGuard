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
    // Current modeled room temperature in Fahrenheit.
    public let temperatureF: Double
    // Current modeled room relative humidity in percent.
    public let humidityPercent: Double

    // Memberwise initializer for a single twin state snapshot.
    public init(temperatureF: Double, humidityPercent: Double) {
        self.temperatureF = temperatureF
        self.humidityPercent = humidityPercent
    }

    // Initial state from the physical system design.
    public static let initial = DigitalTwinState(
        temperatureF: 78.0,
        humidityPercent: 51.0
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
    // Enemy-emulation-only tracking gains that pull state toward injected setpoints.
    public static let qSetpointTrack: Double = 0.003
    public static let hSetpointTrack: Double = 0.003

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

    public static func step(state: DigitalTwinState, command: OperationalCommandBody) -> DigitalTwinState {
        step(
            state: state,
            fanSpeedPercent: command.fanSpeedPercent,
            valvePositionPercent: command.valvePositionPercent,
            equipmentPower: command.equipmentPower
        )
    }

    // Applies one model step for enemy-emulation typed commands.
    public static func step(state: DigitalTwinState, command: EnemyCommandBody) -> DigitalTwinState {
        step(
            state: state,
            fanSpeedPercent: command.fanSpeedPercent,
            valvePositionPercent: command.valvePositionPercent,
            equipmentPower: command.equipmentPower,
            temperatureSetpointF: command.temperatureSetpointF,
            humiditySetpointPercent: command.humiditySetpointPercent
        )
    }

    private static func step(
        state: DigitalTwinState,
        fanSpeedPercent: Double,
        valvePositionPercent: Double,
        equipmentPower: Bool,
        temperatureSetpointF: Double? = nil,
        humiditySetpointPercent: Double? = nil
    ) -> DigitalTwinState {
        // Convert actuator percentages to normalized [0,1] model inputs.
        let fanNormalized = normalizePercent(fanSpeedPercent) // (F)
        let valveNormalized = normalizePercent(valvePositionPercent) // (V)
        // Represent equipment power as a binary disturbance input.
        let powerDisturbance = equipmentPower ? 1.0 : 0.0 // (P)
        // Enemy emulation can bias model evolution toward injected setpoints.
        let temperatureSetpointTerm = temperatureSetpointF.map { qSetpointTrack * ($0 - state.temperatureF) } ?? 0.0
        let humiditySetpointTerm = humiditySetpointPercent.map { hSetpointTrack * ($0 - state.humidityPercent) } ?? 0.0

        // Temperature update: internal heat load - cooling effect + ambient drift.
        let nextTemperature = state.temperatureF + dtSeconds * (
            qLoad * powerDisturbance
            - qCool * (fanNormalized * valveNormalized)
            + qDrift * (ambientTemperatureF - state.temperatureF)
            + temperatureSetpointTerm
        )

        // Humidity update: moisture load - dehumidification + ambient drift.
        let nextHumidityRaw = state.humidityPercent + dtSeconds * (
            hLoad * powerDisturbance
            - hDehum * (fanNormalized * valveNormalized)
            + hDrift * (ambientHumidityPercent - state.humidityPercent)
            + humiditySetpointTerm
        )
        // Keep humidity within physically valid bounds.
        let nextHumidity = clamp(nextHumidityRaw, to: physicalHumidityRangePercent)

        return DigitalTwinState(
            temperatureF: nextTemperature,
            humidityPercent: nextHumidity
        )
    }

    // Typed operational overload that reuses the common simulate implementation.
    public static func simulate(
        state initialState: DigitalTwinState,
        command: OperationalCommandBody,
        seconds: Double
    ) -> [DigitalTwinState] {
        simulate(
            state: initialState,
            fanSpeedPercent: command.fanSpeedPercent,
            valvePositionPercent: command.valvePositionPercent,
            equipmentPower: command.equipmentPower,
            seconds: seconds
        )
    }

    // Typed enemy overload that reuses the common simulate implementation.
    public static func simulate(
        state initialState: DigitalTwinState,
        command: EnemyCommandBody,
        seconds: Double
    ) -> [DigitalTwinState] {
        simulate(
            state: initialState,
            fanSpeedPercent: command.fanSpeedPercent,
            valvePositionPercent: command.valvePositionPercent,
            equipmentPower: command.equipmentPower,
            temperatureSetpointF: command.temperatureSetpointF,
            humiditySetpointPercent: command.humiditySetpointPercent,
            seconds: seconds
        )
    }

    private static func simulate(
        state initialState: DigitalTwinState,
        fanSpeedPercent: Double,
        valvePositionPercent: Double,
        equipmentPower: Bool,
        temperatureSetpointF: Double? = nil,
        humiditySetpointPercent: Double? = nil,
        seconds: Double
    ) -> [DigitalTwinState] {
        // Negative/zero horizons produce no forecast samples.
        guard seconds > 0 else {
            return []
        }

        // Convert horizon to discrete dt-sized simulation steps.
        let stepCount = Int((seconds / dtSeconds).rounded(.down))
        guard stepCount > 0 else {
            return []
        }

        // Preallocate output trajectory for predictable append performance.
        var states: [DigitalTwinState] = []
        states.reserveCapacity(stepCount)
        var current = initialState

        // Reapply same command each step to generate a forward trajectory.
        for _ in 0..<stepCount {
            let next = step(
                state: current,
                fanSpeedPercent: fanSpeedPercent,
                valvePositionPercent: valvePositionPercent,
                equipmentPower: equipmentPower,
                temperatureSetpointF: temperatureSetpointF,
                humiditySetpointPercent: humiditySetpointPercent
            )
            states.append(next)
            current = next
        }

        return states
    }

    // Converts a percent input (0...100) to model scale (0...1).
    private static func normalizePercent(_ value: Double) -> Double {
        value / 100.0
    }

    // Bounds a value to a closed numeric range.
    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
