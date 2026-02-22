//  GatewayResponse.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/
//  Models the response payload returned by the gateway.

import Foundation

// Delivery status reported by the gateway.
enum DeliveryStatus: String, Codable {
    case delivered
    case failed
}

// Execution status reported by the gateway.
enum ExecutionStatus: String, Codable {
    case succeeded
    case failed
}

// Codable response envelope expected from the gateway over NDJSON.
struct GatewayResponse: Codable {
    let id: Int
    let deliveryStatus: DeliveryStatus
    let executionStatus: ExecutionStatus
    let message: String?
    let timestamp: String
}
