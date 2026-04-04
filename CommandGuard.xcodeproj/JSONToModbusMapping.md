# JSON to Modbus TCP Mapping

This document defines how CommandGuard command payloads are converted into Modbus TCP frames.

## Protocol Scope

- Protocol: Modbus TCP
- Unit ID: `1`
- Register write function code: `0x10` (Write Multiple Registers)
- Coil write function code: `0x05` (Write Single Coil)

## Address Map

- `fanSpeedPercent` -> Holding Register `40001` (address `0x0000`)
- `valvePositionPercent` -> Holding Register `40002` (address `0x0001`)
- `temperatureSetpointF` -> Holding Register `40003` (address `0x0002`) (enemy command)
- `humiditySetpointPercent` -> Holding Register `40004` (address `0x0003`) (enemy command)
- `equipmentPower` -> Coil `00001` (address `0x0000`)

## Scaling Rules

- `fanSpeedPercent`: clamped to `0...100`, rounded to whole number, stored as `UInt16`
- `valvePositionPercent`: clamped to `0...100`, rounded to whole number, stored as `UInt16`
- `temperatureSetpointF`: rounded to whole number, clamped to `0...65535`, stored as `UInt16`
- `humiditySetpointPercent`: rounded to whole number, clamped to `0...65535`, stored as `UInt16`
- `equipmentPower`:
  - `true` -> `0xFF00`
  - `false` -> `0x0000`

## Frame Construction

Each accepted command produces two Modbus TCP ADUs:

1. Register write ADU (`FC16`)
2. Power coil ADU (`FC05`)

MBAP header format (7 bytes):

- Transaction ID (2 bytes)
- Protocol ID (`0x0000`) (2 bytes)
- Length (2 bytes): `1 + PDU length`
- Unit ID (1 byte)

## Operational Command Mapping

Operational command mapping:

- `fanSpeedPercent` -> register value 1 in FC16 payload
- `valvePositionPercent` -> register value 2 in FC16 payload
- `equipmentPower` -> FC05 coil value (`0xFF00` on, `0x0000` off)

Register payload starts at `0x0000` and writes 2 registers.

### Example

Input (operational):

- `fanSpeedPercent = 60`
- `valvePositionPercent = 40`
- `equipmentPower = true`

Value mapping:

- `fanSpeedPercent (60)` -> `0x003C` -> register `40001`
- `valvePositionPercent (40)` -> `0x0028` -> register `40002`
- `equipmentPower (true)` -> `0xFF00` -> coil `00001`

Register PDU (`FC16`):

`10 00 00 00 02 04 00 3C 00 28`

Register PDU breakdown:

- `10` -> function code `0x10` (Write Multiple Registers)
- `00 00` -> starting register address `0x0000` (holding register `40001`)
- `00 02` -> quantity of registers to write = `2`
- `04` -> byte count of register data that follows = `4` bytes (`2 registers * 2 bytes`)
- `00 3C` -> register `40001` (`fanSpeedPercent = 60`)
- `00 28` -> register `40002` (`valvePositionPercent = 40`)

Register ADU with TX=1:

`00 01 00 00 00 0B 01 10 00 00 00 02 04 00 3C 00 28`

Register ADU breakdown:

- `00 01` -> transaction ID = `1`
- `00 00` -> protocol ID = `0` (Modbus TCP)
- `00 0B` -> length = `11` bytes (`unitId + PDU`)
- `01` -> unit ID = `1`
- `10 00 00 00 02 04 00 3C 00 28` -> register PDU payload

Power PDU (`FC05`):

`05 00 00 FF 00`

Power PDU breakdown:

- `05` -> function code `0x05` (Write Single Coil)
- `00 00` -> coil address `0x0000` (coil `00001`)
- `FF 00` -> coil ON value (`equipmentPower = true`)

Power ADU with TX=2:

`00 02 00 00 00 06 01 05 00 00 FF 00`

Power ADU breakdown:

- `00 02` -> transaction ID = `2`
- `00 00` -> protocol ID = `0` (Modbus TCP)
- `00 06` -> length = `6` bytes (`unitId + PDU`)
- `01` -> unit ID = `1`
- `05 00 00 FF 00` -> power PDU payload

## Enemy Command Mapping

Enemy command mapping:

- `fanSpeedPercent` -> register value 1 in FC16 payload
- `valvePositionPercent` -> register value 2 in FC16 payload
- `temperatureSetpointF` -> register value 3 in FC16 payload
- `humiditySetpointPercent` -> register value 4 in FC16 payload
- `equipmentPower` -> FC05 coil value (`0xFF00` on, `0x0000` off)

Register payload starts at `0x0000` and writes 4 registers.

### Example

Input (enemy):

- `fanSpeedPercent = 100`
- `valvePositionPercent = 0`
- `temperatureSetpointF = 95`
- `humiditySetpointPercent = 10`
- `equipmentPower = true`

Value mapping:

- `fanSpeedPercent (100)` -> `0x0064` -> register `40001`
- `valvePositionPercent (0)` -> `0x0000` -> register `40002`
- `temperatureSetpointF (95)` -> `0x005F` -> register `40003`
- `humiditySetpointPercent (10)` -> `0x000A` -> register `40004`
- `equipmentPower (true)` -> `0xFF00` -> coil `00001`

Register PDU (`FC16`):

`10 00 00 00 04 08 00 64 00 00 00 5F 00 0A`

FC16 header breakdown (`10 00 00 00 04 08`):

- `10` -> function code `0x10` (Write Multiple Registers)
- `00 00` -> starting register address `0x0000` (holding register `40001`)
- `00 04` -> quantity of registers to write = `4`
- `08` -> byte count of register data that follows = `8` bytes (`4 registers * 2 bytes`)

Register data bytes that follow (`00 64 00 00 00 5F 00 0A`):

- `00 64` -> register `40001` (`fanSpeedPercent = 100`)
- `00 00` -> register `40002` (`valvePositionPercent = 0`)
- `00 5F` -> register `40003` (`temperatureSetpointF = 95`)
- `00 0A` -> register `40004` (`humiditySetpointPercent = 10`)

Register ADU with TX=1:

`00 01 00 00 00 0F 01 10 00 00 00 04 08 00 64 00 00 00 5F 00 0A`

Register ADU breakdown:

- `00 01` -> transaction ID = `1`
- `00 00` -> protocol ID = `0` (Modbus TCP)
- `00 0F` -> length = `15` bytes (`unitId + PDU`)
- `01` -> unit ID = `1`
- `10 00 00 00 04 08 00 64 00 00 00 5F 00 0A` -> register PDU payload

Power PDU (`FC05`):

`05 00 00 FF 00`

Power PDU breakdown:

- `05` -> function code `0x05` (Write Single Coil)
- `00 00` -> coil address `0x0000` (coil `00001`)
- `FF 00` -> coil ON value (`equipmentPower = true`)

Power ADU with TX=2:

`00 02 00 00 00 06 01 05 00 00 FF 00`

Power ADU breakdown:

- `00 02` -> transaction ID = `2`
- `00 00` -> protocol ID = `0` (Modbus TCP)
- `00 06` -> length = `6` bytes (`unitId + PDU`)
- `01` -> unit ID = `1`
- `05 00 00 FF 00` -> power PDU payload

## Notes

- Transaction IDs are sequential per command (`start`, then `start + 1`).
- Modbus TCP uses MBAP framing and does not use RTU CRC fields.
- Rejected commands may appear in gateway history without Modbus frame metadata depending on parse/validation outcome.
