//  GatewayKeyStore.swift
//  CommandGuard
//
/*
This file was developed with the assistance of generative AI tools.
All AI-generated content was reviewed, tested for correctness, and verified by Luke Arsenault.
*/

import Foundation

// Stores trusted public keys used to verify incoming command signatures.
struct GatewayKeyStore {
    // Map keyId -> Base64-encoded P-256 public key (rawRepresentation).
    // Replace the placeholder with the exported public key string from the sender.
    static let publicKeys: [String: String] = [
        "Key-01": "24efmHe49EVLrYdLzC/CtGMzj8M2KpxgxPrjMhWhYPsk0GZcDnAPRUbUq1XFHiaWeur7CAjFrSFQdjyytLzCLQ=="
    ]
}
