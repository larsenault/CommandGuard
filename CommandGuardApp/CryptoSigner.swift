//  CryptoSigner.swift
//  CommandGuard
//
/*
This file was developed with the assistance of the generative AI tool ChatGPT. All pieces of this file have been assisted by AI.
All AI-generated content was reviewed for understanding and cleanliness, tested for correctness and expected results,
and verified by Luke Arsenault.
*/
//  ECDSA P-256 signer with a Keychain-backed private key. Generates or loads the key,
//  signs data using CryptoKit, and returns a Base64-encoded signature along with a keyId.

import Foundation
import CryptoKit
import Security

// Errors that can occur during private key management and signing operations.
public enum CryptoSignerError: Error {
    case keyGenerationFailed
    case keySaveFailed(OSStatus)
    case keyLoadFailed(OSStatus)
    case keyDataConversionFailed
    case signingFailed
}

// CryptoSigner manages an ECDSA P-256 signing key in the Keychain and provides a method to sign data.
public final class CryptoSigner {
    // Application tag used to store and locate the key in the Keychain
    private let keyTag: String
    // Identifier returned with signatures so the verifier can select the correct public key
    private let keyId: String

    // Initialize the signer with a Keychain tag and a key identifier (for server-side key selection)
    public init(keyTag: String = "com.commandguard.signingkey", keyId: String = "Key-01") {
        self.keyTag = keyTag
        self.keyId = keyId
    }

    // Signs the provided data using ECDSA P-256 and returns a Base64 signature and keyId.
    // - Parameter data: Canonical bytes to sign (sorted-keys JSON of the envelope without signature).
    // - Returns: Tuple of (Base64 encoded signature, keyId).
    // - Throws: CryptoSignerError if key load/generation or signing fails.
    public func sign(data: Data) throws -> (String, String) {
        let privateKey = try loadOrCreatePrivateKey()
        // Sign the data with the private key (ECDSA P-256 + SHA-256 via CryptoKit)
        let signature = try privateKey.signature(for: data)
        // Encoded signature by default
        let der = signature.derRepresentation
        // Return standard Base64 of the DER-encoded signature along with the key identifier
        let base64 = der.base64EncodedString()
        return (base64, keyId)
    }

    // MARK: - Key management

    // Loads the signing key from Keychain or generates and stores a new one if missing.
    private func loadOrCreatePrivateKey() throws -> P256.Signing.PrivateKey {
        if let key = try? loadPrivateKey() {
            return key
        }
        let newKey = P256.Signing.PrivateKey()
        try savePrivateKey(newKey)
        return newKey
    }

    // Saves the raw private key material in the Keychain under the configured application tag.
    private func savePrivateKey(_ key: P256.Signing.PrivateKey) throws {
        // Prepare the add-query for SecItemAdd with key class, tag, type, and accessibility
        let tagData = keyTag.data(using: .utf8)!
        let keyData = key.rawRepresentation

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Remove any existing key with the same tag to prevent duplicates
        SecItemDelete(query as CFDictionary)

        // Insert the key into the Keychain and verify success
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CryptoSignerError.keySaveFailed(status) }
    }

    // Loads the raw private key bytes from the Keychain and constructs a CryptoKit private key.
    private func loadPrivateKey() throws -> P256.Signing.PrivateKey {
        // Prepare the match-query to look up the key data by class, tag, and type
        let tagData = keyTag.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnData as String: true
        ]

        // Query the Keychain for the key data
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { throw CryptoSignerError.keyLoadFailed(status) }
        // Ensure the returned item is Data representing the raw private key
        guard let data = item as? Data else { throw CryptoSignerError.keyDataConversionFailed }
        return try P256.Signing.PrivateKey(rawRepresentation: data)
    }
}

