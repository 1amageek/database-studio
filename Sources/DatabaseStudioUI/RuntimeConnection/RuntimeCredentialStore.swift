import Foundation
import Security

struct RuntimeCredentialStore {
    let service: String

    init(service: String = "DatabaseStudio.RuntimeConnection") {
        self.service = service
    }

    func token(for id: UUID) throws -> String? {
        var query = query(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw RuntimeCredentialError.status(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw RuntimeCredentialError.invalidEncoding
        }
        return token
    }

    func save(_ token: String, for id: UUID) throws {
        let query = query(for: id)
        let attributes = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(token.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw RuntimeCredentialError.status(status) }
    }

    func remove(_ id: UUID) throws {
        let status = SecItemDelete(query(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RuntimeCredentialError.status(status)
        }
    }

    private func query(for id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }
}
