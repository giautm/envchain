#if os(Linux)
@preconcurrency import Foundation
import CLibSecret

private let servicePrefix = "envchain-"

struct Keychain {
  static func serviceName(for namespace: String) -> String {
    "\(servicePrefix)\(namespace)"
  }

  nonisolated(unsafe) private static let schema: UnsafeMutablePointer<SecretSchema> = {
    let schema = UnsafeMutablePointer<SecretSchema>.allocate(capacity: 1)
    guard let name = strdup("org.envchain.item"),
          let attrService = strdup("service"),
          let attrAccount = strdup("account") else {
      fputs("Out of memory\n", stderr)
      _exit(1)
    }
    schema.pointee.name = UnsafePointer(name)
    schema.pointee.flags = SECRET_SCHEMA_NONE
    // Attributes: service, account
    withUnsafeMutablePointer(to: &schema.pointee.attributes.0) {
      $0.pointee.name = UnsafePointer(attrService)
      $0.pointee.type = SECRET_SCHEMA_ATTRIBUTE_STRING
    }
    withUnsafeMutablePointer(to: &schema.pointee.attributes.1) {
      $0.pointee.name = UnsafePointer(attrAccount)
      $0.pointee.type = SECRET_SCHEMA_ATTRIBUTE_STRING
    }
    withUnsafeMutablePointer(to: &schema.pointee.attributes.2) {
      $0.pointee.name = nil
      $0.pointee.type = SECRET_SCHEMA_ATTRIBUTE_STRING
    }
    return schema
  }()

  static func saveValue(namespace: String, key: String, value: String, requirePassphrase: Int) {
    if requirePassphrase == 1 {
      fputs("WARNING: --require-passphrase is not supported on Linux; ignoring.\n", stderr)
    }
    let service = serviceName(for: namespace)
    let label = "\(service) - \(key)"
    var error: UnsafeMutablePointer<GError>?
    envchain_secret_password_store(schema, SECRET_COLLECTION_DEFAULT,
      label, value, &error, service, key)
    if let error = error {
      fputs("Error: \(String(cString: error.pointee.message))\n", stderr)
      g_error_free(error)
      exit(10)
    }
  }

  static func searchValues(namespace: String, callback: (String, String) -> Void) -> Bool {
    let service = serviceName(for: namespace)
    var error: UnsafeMutablePointer<GError>?
    let flags = SecretSearchFlags(rawValue: SECRET_SEARCH_ALL.rawValue | SECRET_SEARCH_UNLOCK.rawValue | SECRET_SEARCH_LOAD_SECRETS.rawValue)
    let items: UnsafeMutablePointer<GList>? = envchain_secret_password_search(
      schema, flags, &error, service)
    if let error = error {
      fputs("Error: \(String(cString: error.pointee.message))\n", stderr)
      g_error_free(error)
      exit(10)
    }
    guard let items = items else {
      return false
    }
    var found = false
    var current: UnsafeMutablePointer<GList>? = items
    while let item = current?.pointee.data {
      defer {
        current = current?.pointee.next
      }
      let searchable = item.assumingMemoryBound(to: SecretItem.self)
      guard let attrs = secret_item_get_attributes(searchable) else {
        continue
      }
      defer {
        g_hash_table_unref(attrs)
      }
      guard let account = g_hash_table_lookup(attrs, "account") else {
        continue
      }
      let accountStr = String(cString: account.assumingMemoryBound(to: CChar.self))
      guard let value = secret_item_get_secret(searchable) else {
        continue
      }
      defer {
        secret_value_unref(UnsafeMutableRawPointer(value))
      }
      guard let text = secret_value_get_text(value) else {
        continue
      }
      callback(accountStr, String(cString: text))
      found = true
    }
    g_list_free_full(items, g_object_unref)
    return found
  }

  static func searchNamespaces() -> [String] {
    var error: UnsafeMutablePointer<GError>?
    let flags = SecretSearchFlags(rawValue: SECRET_SEARCH_ALL.rawValue | SECRET_SEARCH_UNLOCK.rawValue)
    let items: UnsafeMutablePointer<GList>? = envchain_secret_password_search_all(
      schema, flags, &error)
    if let error = error {
      g_error_free(error)
      return []
    }
    guard let items = items else {
      return []
    }
    var names = Set<String>()
    var current: UnsafeMutablePointer<GList>? = items
    while let item = current?.pointee.data {
      defer { current = current?.pointee.next }
      let searchable = item.assumingMemoryBound(to: SecretItem.self)
      guard let attrs = secret_item_get_attributes(searchable) else { continue }
      defer { g_hash_table_unref(attrs) }
      guard let service = g_hash_table_lookup(attrs, "service") else { continue }
      let serviceStr = String(cString: service.assumingMemoryBound(to: CChar.self))
      guard serviceStr.hasPrefix(servicePrefix) else { continue }
      names.insert(String(serviceStr.dropFirst(servicePrefix.count)))
    }
    g_list_free_full(items, g_object_unref)
    return names.sorted()
  }

  static func deleteValue(namespace: String, key: String) {
    let service = serviceName(for: namespace)
    var error: UnsafeMutablePointer<GError>?
    _ = envchain_secret_password_clear(
      schema, &error, service, key)
    if let error = error {
      g_error_free(error)
    }
  }
}
#endif
