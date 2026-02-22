//  GatewaySignatureVerifier.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/

import CryptoKit
import Foundation

// Verifies command signatures against trusted gateway public keys.
struct GatewaySignatureVerifier {
    // Errors describing why verification failed.
    enum VerificationError: Error {
        case missingSignature
        case unsupportedAlgorithm
        case unknownKeyId
        case invalidPublicKey
        case invalidSignature
    }

    // Validates the signature on an incoming command envelope.
    func verify(envelope: CommandEnvelope) throws {
        // Ensure the envelope includes a signature.
        guard let signature = envelope.signature else {
            throw VerificationError.missingSignature
        }
        // Enforce the expected algorithm label.
        guard signature.alg == "ECDSA_P256_SHA256" else {
            throw VerificationError.unsupportedAlgorithm
        }
        // Look up the public key for this signature.
        guard let keyBase64 = GatewayKeyStore.publicKeys[signature.keyId] else {
            throw VerificationError.unknownKeyId
        }
        // Decode the Base64 public key into raw key bytes.
        guard let keyData = Data(base64Encoded: keyBase64) else {
            throw VerificationError.invalidPublicKey
        }
        // Build the CryptoKit public key from raw bytes.
        let publicKey: P256.Signing.PublicKey
        do {
            publicKey = try P256.Signing.PublicKey(rawRepresentation: keyData)
        } catch {
            throw VerificationError.invalidPublicKey
        }
        // Decode the signature from Base64 DER format.
        guard let signatureData = Data(base64Encoded: signature.value) else {
            throw VerificationError.invalidSignature
        }
        let ecdsaSignature: P256.Signing.ECDSASignature
        do {
            ecdsaSignature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        } catch {
            throw VerificationError.invalidSignature
        }
        // Recreate the canonical JSON bytes used for signing.
        let canonical = try encodeCanonicalEnvelope(envelope)
        // Validate the signature against the canonical payload.
        guard publicKey.isValidSignature(ecdsaSignature, for: canonical) else {
            throw VerificationError.invalidSignature
        }
    }
}
