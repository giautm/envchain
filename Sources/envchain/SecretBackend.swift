/// A unified interface for accessing secrets, used by both
/// the local Keychain backend and the remote socket client.
protocol SecretBackend: Sendable {
  func searchNamespaces() throws -> [String]
  func searchValues(namespace: String) throws -> (
    values: [String: String], found: Bool
  )
  func saveValue(
    namespace: String, key: String, value: String, requirePassphrase: Int
  ) throws
  func deleteValue(namespace: String, key: String) throws
}

enum BackendValidationError: Error, CustomStringConvertible {
  case invalidNamespace(String)
  case invalidEnvKey(String)

  var description: String {
    switch self {
    case .invalidNamespace(let name):
      return "Invalid namespace name: \(name)"
    case .invalidEnvKey(let key):
      return "Invalid environment variable name: \(key)"
    }
  }
}

extension Unicode.Scalar {
  fileprivate var isASCIILetter: Bool {
    ("A"..."Z") ~= self || ("a"..."z") ~= self
  }
  fileprivate var isASCIIDigit: Bool {
    ("0"..."9") ~= self
  }
}

private let deniedEnvKeys: Set<String> = [
  "LD_PRELOAD", "LD_LIBRARY_PATH",
  "DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH",
]

func isValidEnvKey(_ key: String) -> Bool {
  guard !key.isEmpty else {
    return false
  }
  let scalars = key.unicodeScalars
  guard let first = scalars.first else {
    return false
  }
  guard first.isASCIILetter || first == "_" else {
    return false
  }
  for ch in scalars.dropFirst() {
    guard ch.isASCIILetter || ch.isASCIIDigit || ch == "_" else {
      return false
    }
  }
  return !deniedEnvKeys.contains(key)
}

private func isValidNamespace(_ name: String) -> Bool {
  guard !name.isEmpty, !name.contains("\0"), name.utf8.count <= 255 else {
    return false
  }
  return true
}

/// Decorator that validates namespace/key inputs before delegating to the wrapped backend.
struct ValidatingBackend: SecretBackend {
  private let inner: SecretBackend

  init(wrapping backend: SecretBackend) {
    self.inner = backend
  }

  func searchNamespaces() throws -> [String] {
    try inner.searchNamespaces()
  }

  func searchValues(namespace: String) throws -> (
    values: [String: String], found: Bool
  ) {
    guard isValidNamespace(namespace) else {
      throw BackendValidationError.invalidNamespace(namespace)
    }
    return try inner.searchValues(namespace: namespace)
  }

  func saveValue(
    namespace: String, key: String, value: String, requirePassphrase: Int
  ) throws {
    guard isValidNamespace(namespace) else {
      throw BackendValidationError.invalidNamespace(namespace)
    }
    guard isValidEnvKey(key) else {
      throw BackendValidationError.invalidEnvKey(key)
    }
    try inner.saveValue(
      namespace: namespace, key: key, value: value,
      requirePassphrase: requirePassphrase)
  }

  func deleteValue(namespace: String, key: String) throws {
    guard isValidNamespace(namespace) else {
      throw BackendValidationError.invalidNamespace(namespace)
    }
    try inner.deleteValue(namespace: namespace, key: key)
  }
}

/// Returns the appropriate secret backend based on whether
/// `ENVCHAIN_HOST` is set in the environment.
func currentBackend() -> SecretBackend {
  return ValidatingBackend(wrapping: Keychain())
}
