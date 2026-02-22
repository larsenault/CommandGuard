//  GatewayService.swift
//  CommandGuard
//
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/
//  Represents a discovered Bonjour service for the gateway picker.

import Foundation
import Network

// Represents a discovered Bonjour service for the gateway picker.
struct GatewayService: Identifiable, Equatable {
    // Stable identifier derived from the service endpoint.
    let id: String
    // Display name reported by Bonjour (may be empty).
    let name: String
    // Raw Network framework endpoint used to connect later.
    let endpoint: NWEndpoint

    // Human-friendly name used in the picker UI.
    var displayName: String {
        name.isEmpty ? id : name
    }

    // Build a GatewayService from a browser result.
    init(result: NWBrowser.Result) {
        self.endpoint = result.endpoint
        self.id = Self.endpointIdentifier(result.endpoint)
        self.name = Self.endpointDisplayName(result.endpoint)
    }

    // Creates a repeatable identifier for a given endpoint.
    // This keeps picker selection stable even if the list order changes.
    private static func endpointIdentifier(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case let .service(name, type, domain, _):
            // Use the service tuple to avoid collisions between services.
            return "service:\(name).\(type).\(domain)"
        default:
            // Fallback includes endpoint type and value for uniqueness.
            return endpoint.debugDescription
        }
    }

    // Extracts a displayable name for the endpoint when possible.
    // This favors user-facing labels over internal identifiers.
    private static func endpointDisplayName(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case let .service(name, _, _, _):
            // Bonjour service name shown to the user.
            return name
        case let .hostPort(host, port):
            // Fallback for direct host:port endpoints.
            return "\(host):\(port)"
        default:
            // Last resort: show the endpoint description.
            return endpoint.debugDescription
        }
    }
}
