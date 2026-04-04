//  ModbusEncoder.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import Foundation

// Builds Modbus TCP frames from validated operational command values.
enum ModbusTCPEncoder {
    struct EncodedFrame: Equatable {
        let transactionId: UInt16
        let bytes: Data

        // Byte 0x0​C becomes "0​C".
        var hexString: String {
            bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
    }

    struct EncodedOperationalFrames: Equatable {
        let registerFrame: EncodedFrame
        let powerFrame: EncodedFrame
    }

    // Takes an operational command and creates two Modbus TCP frames:
    // one FC16 write for fan/valve registers and one FC05 write for power.
    static func encodeOperational(
        _ command: OperationalCommandBody,
        startingTransactionId: UInt16 = 1
    ) -> EncodedOperationalFrames {
        let mapping = ModbusCommandMapper.mapOperational(command)
        return encodeOperational(mapping, startingTransactionId: startingTransactionId)
    }

    // Uses enemy actuator values (fan/valve/power) to create the same two Modbus TCP frames.
    static func encodeEnemy(
        _ command: EnemyCommandBody,
        startingTransactionId: UInt16 = 1
    ) -> EncodedOperationalFrames {
        let mapping = ModbusCommandMapper.mapEnemy(command)
        return encodeOperational(mapping, startingTransactionId: startingTransactionId)
    }

    // Encodes an already-mapped command into Modbus TCP frames.
    static func encodeOperational(
        _ mapping: OperationalCommandModbusMapping,
        startingTransactionId: UInt16 = 1
    ) -> EncodedOperationalFrames {
        let registerPDU = makeWriteMultipleRegistersPDU(mapping.registerWrite)
        let registerADU = makeTCPADU(
            transactionId: startingTransactionId,
            unitId: mapping.registerWrite.unitId,
            pdu: registerPDU
        )

        let powerTransactionId = startingTransactionId &+ 1
        let powerPDU = makeWriteSingleCoilPDU(mapping.powerWrite)
        let powerADU = makeTCPADU(
            transactionId: powerTransactionId,
            unitId: mapping.powerWrite.unitId,
            pdu: powerPDU
        )

        return EncodedOperationalFrames(
            registerFrame: EncodedFrame(transactionId: startingTransactionId, bytes: registerADU),
            powerFrame: EncodedFrame(transactionId: powerTransactionId, bytes: powerADU)
        )
    }

    // Builds a Modbus TCP ADU (MBAP header + PDU).
    // MBAP layout: transaction id, protocol id (0), length, unit id.
    // The length field includes unit id + PDU bytes.
    private static func makeTCPADU(transactionId: UInt16, unitId: UInt8, pdu: Data) -> Data {
        let protocolId: UInt16 = 0
        let length = UInt16(1 + pdu.count)

        var data = Data()
        data.append(contentsOf: beBytes(transactionId))
        data.append(contentsOf: beBytes(protocolId))
        data.append(contentsOf: beBytes(length))
        data.append(unitId)
        data.append(pdu)
        return data
    }

    // FC16 PDU layout:
    // [function][startAddress][quantity][byteCount][registerValues...]
    private static func makeWriteMultipleRegistersPDU(_ write: ModbusRegisterWrite) -> Data {
        var pdu = Data()
        pdu.append(write.functionCode.rawValue)
        pdu.append(contentsOf: beBytes(write.startAddress))

        let quantity = UInt16(write.values.count)
        pdu.append(contentsOf: beBytes(quantity))

        let byteCount = UInt8(write.values.count * 2)
        pdu.append(byteCount)

        for value in write.values {
            pdu.append(contentsOf: beBytes(value))
        }

        return pdu
    }

    // FC05 PDU layout:
    // [function][coilAddress][coilValue]
    private static func makeWriteSingleCoilPDU(_ write: ModbusCoilWrite) -> Data {
        var pdu = Data()
        pdu.append(write.functionCode.rawValue)
        pdu.append(contentsOf: beBytes(write.address))
        pdu.append(contentsOf: beBytes(write.value))
        return pdu
    }

    private static func beBytes(_ value: UInt16) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
