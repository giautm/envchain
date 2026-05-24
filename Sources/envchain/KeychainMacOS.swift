#if os(macOS)
import Foundation
import Security

private let servicePrefix = "envchain-"

struct Keychain {
  static func serviceName(for namespace: String) -> String {
    "\(servicePrefix)\(namespace)"
  }

  static func saveValue(
    namespace: String, key: String, value: String, requirePassphrase: Int
  ) {
    let service = serviceName(for: namespace)
    let valueData = value.data(using: .utf8)!
    let searchQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    var ref: AnyObject?
    let findStatus = SecItemCopyMatching(searchQuery as CFDictionary, &ref)
    var status: OSStatus
    if findStatus == errSecSuccess {
      // Delete and recreate to update access control attributes
      SecItemDelete(searchQuery as CFDictionary)
    }
    var newItem: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: valueData,
      kSecAttrDescription as String: "envchain",
    ]
    if requirePassphrase == 1 {
      if let accessControl = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlocked,
        .userPresence,
        nil
      ) {
        newItem[kSecAttrAccessControl as String] = accessControl
      }
    } else {
      newItem[kSecAttrAccessible as String] =
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    status = SecItemAdd(newItem as CFDictionary, nil)
    if status != errSecSuccess {
      failWithOSStatus(status)
    }
  }

  static func searchValues(
    namespace: String, callback: (String, String) -> Void
  ) -> Bool {
    let service = serviceName(for: namespace)
    let listQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnAttributes as String: kCFBooleanTrue!,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var listResult: AnyObject?
    let listStatus = SecItemCopyMatching(listQuery as CFDictionary, &listResult)
    if listStatus == errSecItemNotFound {
      return false
    }
    if listStatus != errSecSuccess {
      failWithOSStatus(listStatus)
    }
    guard let items = listResult as? [[String: Any]] else {
      return false
    }
    for item in items {
      guard let account = item[kSecAttrAccount as String] as? String else {
        continue
      }
      let valueQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: kCFBooleanTrue!,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var valueResult: AnyObject?
      let valueStatus = SecItemCopyMatching(
        valueQuery as CFDictionary, &valueResult)
      guard valueStatus == errSecSuccess,
        let data = valueResult as? Data,
        let value = String(data: data, encoding: .utf8)
      else {
        continue
      }
      callback(account, value)
    }
    return true
  }

  static func searchNamespaces() -> [String] {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrDescription as String: "envchain",
      kSecReturnAttributes as String: kCFBooleanTrue!,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return []
    }
    if status != errSecSuccess {
      failWithOSStatus(status)
    }
    guard let items = result as? [[String: Any]] else {
      return []
    }
    var names = Set<String>()
    for item in items {
      if let service = item[kSecAttrService as String] as? String,
        service.hasPrefix(servicePrefix)
      {
        let name = String(service.dropFirst(servicePrefix.count))
        names.insert(name)
      }
    }
    return names.sorted()
  }

  static func deleteValue(namespace: String, key: String) {
    let service = serviceName(for: namespace)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(query as CFDictionary)
  }

  private static func failWithOSStatus(_ status: OSStatus) {
    if let msg = SecCopyErrorMessageString(status, nil) {
      print("Error: \(msg)", to: &stdError)
    } else {
      print("Error: \(status)", to: &stdError)
    }
    exit(10)
  }
}
#endif
