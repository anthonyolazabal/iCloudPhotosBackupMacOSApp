import Foundation
import CryptoKit
import Security
import OSLog
import CommonCrypto

/// Provides client-side encryption for photo files before upload
/// Uses AES-256-GCM for encryption with keys derived from user passphrase
class EncryptionService {
    private let logger = Logger(subsystem: "com.icloudphotosbackup.app", category: "Encryption")

    // Keychain service name
    private let keychainService = "com.icloudphotosbackup.encryption"
    private let keychainAccount = "encryption-key"

    // Encryption parameters
    private static let saltSize = 32 // 256 bits
    private static let nonceSize = 12 // 96 bits for GCM
    private static let pbkdf2Rounds = 100_000

    // MARK: - Initialization

    init() {
        logger.info("EncryptionService initialized")
    }

    // MARK: - Key Management

    /// Check if an encryption key is already configured
    func hasEncryptionKey() -> Bool {
        do {
            _ = try loadKeyFromKeychain()
            return true
        } catch {
            return false
        }
    }

    /// Set up encryption with a user passphrase
    /// Derives a key using PBKDF2 and stores it securely in Keychain
    func setupEncryption(passphrase: String) throws {
        guard !passphrase.isEmpty else {
            throw EncryptionError.invalidPassphrase(reason: "Passphrase cannot be empty")
        }

        guard passphrase.count >= 12 else {
            throw EncryptionError.invalidPassphrase(reason: "Passphrase must be at least 12 characters")
        }

        logger.info("Setting up encryption with new passphrase")

        // Generate random salt
        var salt = Data(count: Self.saltSize)
        let result = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, Self.saltSize, bytes.baseAddress!)
        }

        guard result == errSecSuccess else {
            throw EncryptionError.keyGenerationFailed(reason: "Failed to generate random salt")
        }

        // Derive key from passphrase using PBKDF2
        let key = try deriveKey(from: passphrase, salt: salt)

        // Store both key and salt in Keychain
        try saveKeyToKeychain(key: key, salt: salt)

        logger.info("Encryption setup completed successfully")
    }

    /// Verify the passphrase matches the stored key
    func verifyPassphrase(_ passphrase: String) throws -> Bool {
        let (storedKey, salt) = try loadKeyFromKeychain()
        let derivedKey = try deriveKey(from: passphrase, salt: salt)

        return derivedKey == storedKey
    }

    /// Remove encryption configuration
    func removeEncryption() throws {
        logger.warning("Removing encryption configuration")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EncryptionError.keychainError(status: status)
        }

        logger.info("Encryption configuration removed")
    }

    // MARK: - Encryption/Decryption

    /// Encrypt a file and write to destination
    func encryptFile(at sourceURL: URL, to destinationURL: URL) throws {
        logger.debug("Encrypting file: \(sourceURL.lastPathComponent)")

        // Load encryption key
        let (key, _) = try loadKeyFromKeychain()
        let symmetricKey = SymmetricKey(data: key)

        // Read source file
        let plaintext = try Data(contentsOf: sourceURL)

        // Generate random nonce
        var nonceBytes = [UInt8](repeating: 0, count: Self.nonceSize)
        let result = SecRandomCopyBytes(kSecRandomDefault, Self.nonceSize, &nonceBytes)

        guard result == errSecSuccess else {
            throw EncryptionError.encryptionFailed(reason: "Failed to generate nonce")
        }

        let nonce = try AES.GCM.Nonce(data: Data(nonceBytes))

        // Encrypt
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: nonce)

        // Combine nonce + ciphertext + tag
        // Format: [nonce (12 bytes)][ciphertext][tag (16 bytes)]
        guard let combinedData = sealedBox.combined else {
            throw EncryptionError.encryptionFailed(reason: "Failed to create combined encrypted data")
        }

        // Write to destination
        try combinedData.write(to: destinationURL)

        logger.debug("File encrypted successfully: \(destinationURL.lastPathComponent)")
    }

    /// Decrypt a file and write to destination
    func decryptFile(at sourceURL: URL, to destinationURL: URL) throws {
        logger.debug("Decrypting file: \(sourceURL.lastPathComponent)")

        // Load encryption key
        let (key, _) = try loadKeyFromKeychain()
        let symmetricKey = SymmetricKey(data: key)

        // Read encrypted file
        let combinedData = try Data(contentsOf: sourceURL)

        // Create sealed box from combined data
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)

        // Decrypt
        let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)

        // Write to destination
        try plaintext.write(to: destinationURL)

        logger.debug("File decrypted successfully: \(destinationURL.lastPathComponent)")
    }

    /// Encrypt data in memory and return encrypted data
    func encryptData(_ data: Data) throws -> EncryptedData {
        // Load encryption key
        let (key, _) = try loadKeyFromKeychain()
        let symmetricKey = SymmetricKey(data: key)

        // Generate random nonce
        var nonceBytes = [UInt8](repeating: 0, count: Self.nonceSize)
        let result = SecRandomCopyBytes(kSecRandomDefault, Self.nonceSize, &nonceBytes)

        guard result == errSecSuccess else {
            throw EncryptionError.encryptionFailed(reason: "Failed to generate nonce")
        }

        let nonce = try AES.GCM.Nonce(data: Data(nonceBytes))

        // Encrypt
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey, nonce: nonce)

        guard let combinedData = sealedBox.combined else {
            throw EncryptionError.encryptionFailed(reason: "Failed to create combined encrypted data")
        }

        return EncryptedData(data: combinedData, nonce: Data(nonceBytes))
    }

    /// Decrypt data in memory
    func decryptData(_ encryptedData: EncryptedData) throws -> Data {
        // Load encryption key
        let (key, _) = try loadKeyFromKeychain()
        let symmetricKey = SymmetricKey(data: key)

        // Create sealed box from combined data
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData.data)

        // Decrypt
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    // MARK: - Private Helpers

    private func deriveKey(from passphrase: String, salt: Data) throws -> Data {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw EncryptionError.invalidPassphrase(reason: "Failed to encode passphrase")
        }

        var derivedKeyData = Data(count: 32) // 256 bits

        let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passphraseData.withUnsafeBytes { passphraseBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passphraseBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passphraseData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(Self.pbkdf2Rounds),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw EncryptionError.keyGenerationFailed(reason: "PBKDF2 derivation failed")
        }

        return derivedKeyData
    }

    private func saveKeyToKeychain(key: Data, salt: Data) throws {
        // Combine key and salt for storage
        var combinedData = Data()
        combinedData.append(key)
        combinedData.append(salt)

        // First, delete any existing key
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: combinedData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw EncryptionError.keychainError(status: status)
        }
    }

    private func loadKeyFromKeychain() throws -> (key: Data, salt: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw EncryptionError.keyNotFound
            }
            throw EncryptionError.keychainError(status: status)
        }

        guard let combinedData = item as? Data else {
            throw EncryptionError.keyNotFound
        }

        // Split into key (32 bytes) and salt (32 bytes)
        guard combinedData.count == 64 else {
            throw EncryptionError.invalidKeyData
        }

        let key = combinedData.prefix(32)
        let salt = combinedData.suffix(32)

        return (Data(key), Data(salt))
    }
}

// MARK: - Supporting Types

/// Encrypted data with metadata
struct EncryptedData {
    let data: Data // Combined nonce + ciphertext + tag
    let nonce: Data
}

