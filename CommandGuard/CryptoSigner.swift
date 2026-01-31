//  CryptoSigner.swift
//  CommandGuard
//
//  ECDSA P-256 signer with Keychain-backed private key.

import Foundation
import CryptoKit
import Security

public enum CryptoSignerError: Error {
    case keyGenerationFailed
    case keySaveFailed(OSStatus)
    case keyLoadFailed(OSStatus)
    case keyDataConversionFailed
    case signingFailed
}

public final class CryptoSigner {
    private let keyTag: String
    private let keyId: String

    public init(keyTag: String = "com.commandguard.signingkey", keyId: String = "app-01") {
        self.keyTag = keyTag
        self.keyId = keyId
    }

    // Returns (signatureBase64, keyId)
    public func sign(data: Data) throws -> (String, String) {
        let privateKey = try loadOrCreatePrivateKey()
        let signature = try privateKey.signature(for: data)
        // DER-encoded signature by default; export raw (r||s) is not directly available from CryptoKit.
        // Gateways typically accept DER for ECDSA; if you need raw format, we can add DER->raw conversion.
        let der = signature.derRepresentation
        let base64 = der.base64EncodedString()
        return (base64, keyId)
    }

    // MARK: - Key management

    private func loadOrCreatePrivateKey() throws -> P256.Signing.PrivateKey {
        if let key = try? loadPrivateKey() {
            return key
        }
        let newKey = P256.Signing.PrivateKey()
        try savePrivateKey(newKey)
        return newKey
    }

    private func savePrivateKey(_ key: P256.Signing.PrivateKey) throws {
        let tagData = keyTag.data(using: .utf8)!
        let keyData = key.rawRepresentation

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Delete any existing key with the same tag to avoid duplicates
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CryptoSignerError.keySaveFailed(status) }
    }

    private func loadPrivateKey() throws -> P256.Signing.PrivateKey {
        let tagData = keyTag.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { throw CryptoSignerError.keyLoadFailed(status) }
        guard let data = item as? Data else { throw CryptoSignerError.keyDataConversionFailed }
        return try P256.Signing.PrivateKey(rawRepresentation: data)
    }
}
