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
    enum VerificationError: LocalizedError {
        case missingSignature
        case unsupportedAlgorithm(String)
        case unknownKeyId(String)
        case invalidPublicKey
        case invalidSignature

        var errorDescription: String? {
            switch self {
            case .missingSignature:
                return "Missing signature block"
            case let .unsupportedAlgorithm(algorithm):
                return "Unsupported alg \(algorithm)"
            case let .unknownKeyId(keyId):
                return "Unknown keyId \(keyId)"
            case .invalidPublicKey:
                return "Gateway public key decode failed"
            case .invalidSignature:
                return "Signature bytes invalid or signature mismatch"
            }
        }
    }

    // Validates the signature on a typed incoming command envelope.
    func verifyTyped<Body: Codable>(envelope: TypedCommandEnvelope<Body>) throws {
        guard let signature = envelope.signature else {
            throw VerificationError.missingSignature
        }
        guard signature.alg == "ECDSA_P256_SHA256" else {
            throw VerificationError.unsupportedAlgorithm(signature.alg)
        }
        guard let keyBase64 = GatewayKeyStore.publicKeys[signature.keyId] else {
            throw VerificationError.unknownKeyId(signature.keyId)
        }
        guard let keyData = Data(base64Encoded: keyBase64) else {
            throw VerificationError.invalidPublicKey
        }

        let publicKey: P256.Signing.PublicKey
        do {
            publicKey = try P256.Signing.PublicKey(rawRepresentation: keyData)
        } catch {
            throw VerificationError.invalidPublicKey
        }

        guard let signatureData = Data(base64Encoded: signature.value) else {
            throw VerificationError.invalidSignature
        }

        let ecdsaSignature: P256.Signing.ECDSASignature
        do {
            ecdsaSignature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        } catch {
            throw VerificationError.invalidSignature
        }

        let canonical = try encodeCanonicalEnvelope(envelope)
        guard publicKey.isValidSignature(ecdsaSignature, for: canonical) else {
            throw VerificationError.invalidSignature
        }
    }
}
