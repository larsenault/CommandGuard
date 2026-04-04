//  ModbusModels.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import Foundation

// Modbus TCP only for this project.
enum ModbusTransport {
    case tcp
}

// Function codes currently used by this project mapping.
enum ModbusFunctionCode: UInt8 {
    case writeSingleCoil = 0x05
    case writeMultipleRegisters = 0x10
}

// Intent model for writing one or more contiguous holding registers.
struct ModbusRegisterWrite: Equatable {
    let unitId: UInt8
    let functionCode: ModbusFunctionCode
    let startAddress: UInt16
    let values: [UInt16]
}

// Intent model for writing a single coil.
struct ModbusCoilWrite: Equatable {
    let unitId: UInt8
    let functionCode: ModbusFunctionCode
    let address: UInt16
    let value: UInt16
}

// Combined JSON-to-Modbus representation for one operational command.
struct OperationalCommandModbusMapping: Equatable {
    let registerWrite: ModbusRegisterWrite
    let powerWrite: ModbusCoilWrite
}

// Converts validated operational JSON command fields into Modbus write intents.
enum ModbusCommandMapper {
    // Shared conversion path for actuator controls present in both operational and enemy commands.
    private static func makeActuatorMapping(
        fanSpeedPercent: Double,
        valvePositionPercent: Double,
        equipmentPower: Bool
    ) -> OperationalCommandModbusMapping {
        let fanValue = ModbusRegisterMap.scaledPercentToRegister(fanSpeedPercent)
        let valveValue = ModbusRegisterMap.scaledPercentToRegister(valvePositionPercent)
        let powerValue = ModbusRegisterMap.powerToCoilValue(equipmentPower)

        let registerWrite = ModbusRegisterWrite(
            unitId: ModbusRegisterMap.unitId,
            functionCode: .writeMultipleRegisters,
            startAddress: ModbusRegisterMap.fanSpeedRegisterAddress,
            values: [fanValue, valveValue]
        )

        let powerWrite = ModbusCoilWrite(
            unitId: ModbusRegisterMap.unitId,
            functionCode: .writeSingleCoil,
            address: ModbusRegisterMap.equipmentPowerCoilAddress,
            value: powerValue
        )

        return OperationalCommandModbusMapping(
            registerWrite: registerWrite,
            powerWrite: powerWrite
        )
    }

    static func mapOperational(_ command: OperationalCommandBody) -> OperationalCommandModbusMapping {
        makeActuatorMapping(
            fanSpeedPercent: command.fanSpeedPercent,
            valvePositionPercent: command.valvePositionPercent,
            equipmentPower: command.equipmentPower
        )
    }

    static func mapEnemy(_ command: EnemyCommandBody) -> OperationalCommandModbusMapping {
        let fanValue = ModbusRegisterMap.scaledPercentToRegister(command.fanSpeedPercent)
        let valveValue = ModbusRegisterMap.scaledPercentToRegister(command.valvePositionPercent)
        let temperatureValue = ModbusRegisterMap.scaledWholeValueToRegister(command.temperatureSetpointF)
        let humidityValue = ModbusRegisterMap.scaledWholeValueToRegister(command.humiditySetpointPercent)
        let powerValue = ModbusRegisterMap.powerToCoilValue(command.equipmentPower)

        let registerWrite = ModbusRegisterWrite(
            unitId: ModbusRegisterMap.unitId,
            functionCode: .writeMultipleRegisters,
            startAddress: ModbusRegisterMap.fanSpeedRegisterAddress,
            values: [fanValue, valveValue, temperatureValue, humidityValue]
        )

        let powerWrite = ModbusCoilWrite(
            unitId: ModbusRegisterMap.unitId,
            functionCode: .writeSingleCoil,
            address: ModbusRegisterMap.equipmentPowerCoilAddress,
            value: powerValue
        )

        return OperationalCommandModbusMapping(
            registerWrite: registerWrite,
            powerWrite: powerWrite
        )
    }
}
