import Foundation
import Security
import TadaWordsDomain

public enum KeychainDeviceVoiceprintRepositoryError: Error, Equatable, Sendable {
    case keychain(operation: String, status: OSStatus)
    case invalidStoredTemplate(profileID: ProfileID, details: String)
}

/// Stores only the final embedding template in the local data-protection
/// keychain. `ThisDeviceOnly` and `kSecAttrSynchronizable = false` explicitly
/// prevent backup migration and iCloud Keychain synchronization.
public actor KeychainDeviceVoiceprintRepository: DeviceVoiceprintRepository {
    private let service: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(service: String = "com.tadawords.device-voiceprints") {
        self.service = service
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    public func template(
        for profileID: ProfileID
    ) async throws -> DeviceVoiceprintTemplate? {
        var item: CFTypeRef?
        var query = baseQuery(profileID: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainDeviceVoiceprintRepositoryError.keychain(
                operation: "read",
                status: status
            )
        }
        guard let data = item as? Data else {
            throw KeychainDeviceVoiceprintRepositoryError.invalidStoredTemplate(
                profileID: profileID,
                details: "Keychain item did not contain Data"
            )
        }

        do {
            let template = try decoder.decode(
                DeviceVoiceprintTemplate.self,
                from: data
            )
            guard template.profileID == profileID else {
                throw
                    KeychainDeviceVoiceprintRepositoryError
                    .invalidStoredTemplate(
                        profileID: profileID,
                        details: "Stored profile identity did not match its key"
                    )
            }
            return template
        } catch let error as KeychainDeviceVoiceprintRepositoryError {
            throw error
        } catch {
            throw KeychainDeviceVoiceprintRepositoryError.invalidStoredTemplate(
                profileID: profileID,
                details: String(describing: error)
            )
        }
    }

    public func save(_ template: DeviceVoiceprintTemplate) async throws {
        let data = try encoder.encode(template)
        let query = baseQuery(profileID: template.profileID)
        let values = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            values as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainDeviceVoiceprintRepositoryError.keychain(
                operation: "update",
                status: updateStatus
            )
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] =
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        newItem[kSecAttrSynchronizable as String] = false

        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainDeviceVoiceprintRepositoryError.keychain(
                operation: "add",
                status: addStatus
            )
        }
    }

    public func delete(for profileID: ProfileID) async throws {
        let status = SecItemDelete(baseQuery(profileID: profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainDeviceVoiceprintRepositoryError.keychain(
                operation: "delete",
                status: status
            )
        }
    }

    private func baseQuery(profileID: ProfileID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.rawValue.uuidString,
        ]
    }
}
