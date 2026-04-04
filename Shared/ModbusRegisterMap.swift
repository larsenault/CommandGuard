//  ModbusRegisterMap.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import Foundation

// Central source of truth for translating operational JSON fields into Modbus addresses and write strategy.
enum ModbusRegisterMap {
    // Unit identifier used in Modbus RTU and Modbus TCP requests.
    static let unitId: UInt8 = 1

    // Holding registers (4xxxx)
    // fanSpeedPercent -> 40001 (zero-based address 0x0000)
    static let fanSpeedRegisterAddress: UInt16 = 0x0000
    // valvePositionPercent -> 40002 (zero-based address 0x0001)
    static let valvePositionRegisterAddress: UInt16 = 0x0001

    // Coils (0xxxx)
    // equipmentPower -> 00001 (zero-based address 0x0000)
    static let equipmentPowerCoilAddress: UInt16 = 0x0000

    // Function-code strategy
    // Use FC16 (0x10) to write fan and valve together as contiguous holding registers.
    static let writeMultipleRegistersFunctionCode: UInt8 = 0x10
    // Use FC05 (0x05) to write equipment power as a single coil.
    static let writeSingleCoilFunctionCode: UInt8 = 0x05

    // Percent scaling policy for actuator values.
    // Current project mapping stores percent values as whole-number UInt16 in the range 0...100.
    static let percentMinimum: Double = 0
    static let percentMaximum: Double = 100

    // Converts a percent value to a clamped whole-number Modbus register representation.
    static func scaledPercentToRegister(_ percent: Double) -> UInt16 {
        let clamped = min(max(percent, percentMinimum), percentMaximum)
        return UInt16(clamped.rounded())
    }

    // Modbus coil on/off representations used by FC05.
    static let coilOnValue: UInt16 = 0xFF00
    static let coilOffValue: UInt16 = 0x0000

    static func powerToCoilValue(_ isOn: Bool) -> UInt16 {
        isOn ? coilOnValue : coilOffValue
    }
}
