import Foundation
import OSLog
import Security

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedDataFormat

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            "Could not save your API key to the keychain. Please try again."
        case .loadFailed:
            "Could not read your API key from the keychain."
        case .deleteFailed:
            "Could not remove the saved API key. Please try again."
        case .unexpectedDataFormat:
            "The saved key is in an unexpected format. Please re-enter it."
        }
    }
}

@MainActor
final class KeychainService {
    private let service = "com.sheryahmed.focusframe.anthropic-api-key"
    private let account = "default"

    func saveAPIKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedDataFormat
        }

        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            Logger.keychain.info("api key updated")
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                Logger.keychain.error("api key save failed status=\(addStatus)")
                throw KeychainError.saveFailed(addStatus)
            }
            Logger.keychain.info("api key saved")
            return
        }

        Logger.keychain.error("api key update failed status=\(updateStatus)")
        throw KeychainError.saveFailed(updateStatus)
    }

    func loadAPIKey() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            Logger.keychain.error("api key load failed status=\(status)")
            throw KeychainError.loadFailed(status)
        }

        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedDataFormat
        }

        return key
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            Logger.keychain.info("api key deleted")
            return
        }

        Logger.keychain.error("api key delete failed status=\(status)")
        throw KeychainError.deleteFailed(status)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
