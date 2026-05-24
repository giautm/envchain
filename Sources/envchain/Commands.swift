@preconcurrency import Foundation

private let deniedEnvKeys: Set<String> = [
  "LD_PRELOAD", "LD_LIBRARY_PATH",
  "DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH",
]

extension Unicode.Scalar {
  fileprivate var isASCIILetter: Bool {
    ("A"..."Z") ~= self || ("a"..."z") ~= self
  }
  fileprivate var isASCIIDigit: Bool {
    ("0"..."9") ~= self
  }
}

private func isValidEnvKey(_ key: String) -> Bool {
  guard !key.isEmpty else {
    return false
  }
  let scalars = key.unicodeScalars
  guard let first = scalars.first else {
    return false
  }
  // First character must be ASCII letter or underscore
  guard first.isASCIILetter || first == "_" else {
    return false
  }
  // Remaining characters must be ASCII letters, digits, or underscore
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

func cmdSet(args: ArraySlice<String>) -> Int32 {
  var argv = Array(args)
  var noecho = false
  var requirePassphrase = -1

  while argv.count > 2 {
    guard argv[0].hasPrefix("-") else {
      break
    }
    if argv[0] == "-n" || argv[0] == "--noecho" {
      argv.removeFirst()
      noecho = true
    } else if argv[0] == "-p" || argv[0] == "--require-passphrase" {
      argv.removeFirst()
      requirePassphrase = 1
    } else if argv[0] == "-P" || argv[0] == "--no-require-passphrase" {
      argv.removeFirst()
      requirePassphrase = 0
    } else {
      print("Unknown option: \(argv[0])", to: &stdError)
      return 1
    }
  }
  if argv.count < 2 {
    printHelp()
    return 2
  }
  let name = argv[0]
  guard isValidNamespace(name) else {
    print("Invalid namespace name: \(name)", to: &stdError)
    return 1
  }
  argv.removeFirst()
  for key in argv {
    guard isValidEnvKey(key) else {
      print("Invalid environment variable name: \(key)", to: &stdError)
      return 1
    }
    guard let value = askValue(name: name, key: key, noecho: noecho) else {
      return 1
    }
    Keychain.saveValue(
      namespace: name, key: key, value: value,
      requirePassphrase: requirePassphrase)
  }
  return 0
}

func cmdList(args: ArraySlice<String>) -> Int32 {
  var argv = Array(args)
  var showValue = false
  var target: String? = nil
  while !argv.isEmpty {
    if argv[0] == "--show-value" || argv[0] == "-v" {
      argv.removeFirst()
      showValue = true
    } else {
      if target != nil {
        printHelp()
        return 2
      }
      target = argv[0]
      argv.removeFirst()
    }
  }
  if let target = target {
    guard isValidNamespace(target) else {
      print("Invalid namespace name: \(target)", to: &stdError)
      return 1
    }
    let found = Keychain.searchValues(namespace: target) { key, value in
      if showValue {
        print("\(key)=\(value)")
      } else {
        print(key)
      }
    }
    if !found {
      print("WARNING: namespace `\(target)` not defined.", to: &stdError)
      print(
        "     You can set via running `\(CommandLine.arguments[0]) --set \(target) SOME_ENV_NAME`.\n",
        to: &stdError)
    }
  } else {
    if showValue {
      printHelp()
      return 2
    }
    let namespaces = Keychain.searchNamespaces()
    for ns in namespaces {
      print(ns)
    }
  }
  return 0
}

func cmdUnset(args: ArraySlice<String>) -> Int32 {
  var argv = Array(args)
  if argv.count < 2 {
    printHelp()
    return 2
  }
  let name = argv[0]
  guard isValidNamespace(name) else {
    print("Invalid namespace name: \(name)", to: &stdError)
    return 1
  }
  argv.removeFirst()
  for key in argv {
    Keychain.deleteValue(namespace: name, key: key)
  }
  return 0
}

func cmdJSON(args: ArraySlice<String>) -> Int32 {
  let argv = Array(args)
  if argv.isEmpty {
    printHelp()
    return 2
  }
  let name = argv[0]
  guard isValidNamespace(name) else {
    print("Invalid namespace name: \(name)", to: &stdError)
    return 1
  }
  var dict: [String: String] = [:]
  let found = Keychain.searchValues(namespace: name) { key, value in
    dict[key] = value
  }
  if !found {
    print("WARNING: namespace `\(name)` not defined.", to: &stdError)
    print(
      "     You can set via running `\(CommandLine.arguments[0]) --set \(name) SOME_ENV_NAME`.\n",
      to: &stdError)
    return 1
  }
  guard
    let data = try? JSONSerialization.data(
      withJSONObject: dict, options: [.sortedKeys]),
    let json = String(data: data, encoding: .utf8)
  else {
    print("Failed to serialize JSON", to: &stdError)
    return 1
  }
  print(json)
  return 0
}

func cmdAWSCredential(args: ArraySlice<String>) -> Int32 {
  let argv = Array(args)
  if argv.isEmpty {
    printHelp()
    return 2
  }
  let name = argv[0]
  guard isValidNamespace(name) else {
    print("Invalid namespace name: \(name)", to: &stdError)
    return 1
  }
  var dict: [String: String] = [:]
  let found = Keychain.searchValues(namespace: name) { key, value in
    dict[key] = value
  }
  if !found {
    print("WARNING: namespace `\(name)` not defined.", to: &stdError)
    print(
      "     You can set via running `\(CommandLine.arguments[0]) --set \(name) SOME_ENV_NAME`.\n",
      to: &stdError)
    return 1
  }
  var credential: [String: Any] = ["Version": 1]
  if let v = dict["AWS_ACCESS_KEY_ID"] {
    credential["AccessKeyId"] = v
  }
  if let v = dict["AWS_SECRET_ACCESS_KEY"] {
    credential["SecretAccessKey"] = v
  }
  if let v = dict["AWS_SESSION_TOKEN"] {
    credential["SessionToken"] = v
  }
  if let v = dict["AWS_CREDENTIAL_EXPIRATION"] {
    credential["Expiration"] = v
  }
  guard
    let data = try? JSONSerialization.data(
      withJSONObject: credential, options: [.sortedKeys]),
    let json = String(data: data, encoding: .utf8)
  else {
    print("Failed to serialize JSON", to: &stdError)
    return 1
  }
  print(json)
  return 0
}

func cmdExec(args: ArraySlice<String>) -> Int32 {
  var argv = Array(args)
  if argv.count < 2 {
    printHelp()
    return 2
  }
  let namespaceArg = argv[0]
  argv.removeFirst()
  let namespaces = namespaceArg.split(separator: ",").map(String.init)
  for name in namespaces {
    guard isValidNamespace(name) else {
      print("Invalid namespace name: \(name)", to: &stdError)
      return 1
    }
    let found = Keychain.searchValues(namespace: name) { key, value in
      guard isValidEnvKey(key) else {
        print(
          "WARNING: skipping invalid key \"\(key)\" in namespace `\(name)`",
          to: &stdError)
        return
      }
      setenv(key, value, 1)
    }
    if !found {
      print("WARNING: namespace `\(name)` not defined.", to: &stdError)
      print(
        "     You can set via running `\(CommandLine.arguments[0]) --set \(name) SOME_ENV_NAME`.\n",
        to: &stdError)
    }
  }
  let exe = argv[0]
  var cArgs: [UnsafeMutablePointer<CChar>?] = []
  for arg in argv {
    guard let dup = strdup(arg) else {
      for ptr in cArgs {
        free(ptr)
      }
      print("Out of memory", to: &stdError)
      return 1
    }
    cArgs.append(dup)
  }
  cArgs.append(nil)
  execvp(exe, &cArgs)
  let err = String(cString: strerror(errno))
  for ptr in cArgs {
    free(ptr)
  }
  print("execvp failed: \(err)", to: &stdError)
  return 1
}

// MARK: - Input Helpers

nonisolated(unsafe) private var savedTermios: termios?

private func restoreTerminal(_: Int32) {
  if var attrs = savedTermios {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &attrs)
  }
  let nl: [UInt8] = [0x0A]
  nl.withUnsafeBufferPointer { _ = write(STDERR_FILENO, $0.baseAddress!, 1) }
  _exit(130)
}

func noechoRead(prompt: String) -> String? {
  var oldAttrs = termios()
  guard tcgetattr(STDIN_FILENO, &oldAttrs) == 0 else {
    if errno == ENOTTY {
      print("--noecho (-n) requires stdin to be a terminal", to: &stdError)
    } else {
      print(
        "oops when attempted to read: \(String(cString: strerror(errno)))",
        to: &stdError)
    }
    return nil
  }
  var newAttrs = oldAttrs
  newAttrs.c_lflag &= ~tcflag_t(ECHO)
  guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &newAttrs) == 0 else {
    print("tcsetattr failed", to: &stdError)
    exit(10)
  }
  savedTermios = oldAttrs
  signal(SIGINT, restoreTerminal)
  signal(SIGTERM, restoreTerminal)
  print("\(prompt) (noecho):", terminator: "", to: &stdError)
  let input = readLine()
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &oldAttrs)
  savedTermios = nil
  signal(SIGINT, SIG_DFL)
  signal(SIGTERM, SIG_DFL)
  print("", to: &stdError)
  return input
}

func askValue(name: String, key: String, noecho: Bool) -> String? {
  let prompt = "\(name).\(key)"
  if noecho {
    return noechoRead(prompt: prompt)
  } else {
    print("\(prompt): ", terminator: "", to: &stdError)
    return readLine()
  }
}
