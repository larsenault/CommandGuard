//  GatewayResponse.swift
//  CommandGuard
//
/*
This file was developed with the assistance of generative AI tools.
All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
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
