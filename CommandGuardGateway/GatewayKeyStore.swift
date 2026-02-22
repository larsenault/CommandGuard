//  GatewayKeyStore.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import Foundation

// Stores trusted public keys used to verify incoming command signatures.
struct GatewayKeyStore {
    // Map keyId -> Base64-encoded P-256 public key (rawRepresentation).
    // Replace the placeholder with the exported public key string from the sender.
    static let publicKeys: [String: String] = [
        "Key-01": "uaDyMziWiOXMthsIOd7xMZDqKJHyqTD2CqZMCuUd1dRAuzthJmYCQAUBwWO4RAaESlg/GGsdyph0Lww0Y22LVA=="
    ]
}
