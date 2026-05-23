@preconcurrency import Foundation

private func isValidEnvKey(_ key: String) -> Bool {
  guard !key.isEmpty, !key.contains("="), !key.contains("\0") else {
    return false
  }
  return true
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
    guard argv[0].hasPrefix("-") else { break }
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
      fputs("Unknown option: \(argv[0])\n", stderr)
      return 1
    }
  }
  if argv.count < 2 { abortWithHelp() }
  let name = argv[0]
  guard isValidNamespace(name) else {
    fputs("Invalid namespace name: \(name)\n", stderr)
    return 1
  }
  argv.removeFirst()
  for key in argv {
    guard isValidEnvKey(key) else {
      fputs("Invalid environment variable name: \(key)\n", stderr)
      return 1
    }
    guard let value = askValue(name: name, key: key, noecho: noecho) else {
      return 1
    }
    Keychain.saveValue(namespace: name, key: key, value: value, requirePassphrase: requirePassphrase)
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
      if target != nil { abortWithHelp() }
      target = argv[0]
      argv.removeFirst()
    }
  }
  if let target = target {
    guard isValidNamespace(target) else {
      fputs("Invalid namespace name: \(target)\n", stderr)
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
      fputs("WARNING: namespace `\(target)` not defined.\n", stderr)
      fputs("     You can set via running `\(CommandLine.arguments[0]) --set \(target) SOME_ENV_NAME`.\n\n", stderr)
    }
  } else {
    if showValue { abortWithHelp() }
    let namespaces = Keychain.searchNamespaces()
    for ns in namespaces {
      print(ns)
    }
  }
  return 0
}

func cmdUnset(args: ArraySlice<String>) -> Int32 {
  var argv = Array(args)
  if argv.count < 2 { abortWithHelp() }
  let name = argv[0]
  guard isValidNamespace(name) else {
    fputs("Invalid namespace name: \(name)\n", stderr)
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
  if argv.isEmpty { abortWithHelp() }
  let name = argv[0]
  guard isValidNamespace(name) else {
    fputs("Invalid namespace name: \(name)\n", stderr)
    return 1
  }
  var dict: [String: String] = [:]
  let found = Keychain.searchValues(namespace: name) { key, value in
    dict[key] = value
  }
  if !found {
    fputs("WARNING: namespace `\(name)` not defined.\n", stderr)
    fputs("     You can set via running `\(CommandLine.arguments[0]) --set \(name) SOME_ENV_NAME`.\n\n", stderr)
    return 1
  }
  guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8) else {
    fputs("Failed to serialize JSON\n", stderr)
    return 1
  }
  print(json)
  return 0
}

func cmdAWSCredential(args: ArraySlice<String>) -> Int32 {
  let argv = Array(args)
  if argv.isEmpty { abortWithHelp() }
  let name = argv[0]
  guard isValidNamespace(name) else {
    fputs("Invalid namespace name: \(name)\n", stderr)
    return 1
  }
  var dict: [String: String] = [:]
  let found = Keychain.searchValues(namespace: name) { key, value in
    dict[key] = value
  }
  if !found {
    fputs("WARNING: namespace `\(name)` not defined.\n", stderr)
    fputs("     You can set via running `\(CommandLine.arguments[0]) --set \(name) SOME_ENV_NAME`.\n\n", stderr)
    return 1
  }
  var credential: [String: Any] = ["Version": 1]
  if let v = dict["AWS_ACCESS_KEY_ID"] { credential["AccessKeyId"] = v }
  if let v = dict["AWS_SECRET_ACCESS_KEY"] { credential["SecretAccessKey"] = v }
  if let v = dict["AWS_SESSION_TOKEN"] { credential["SessionToken"] = v }
  if let v = dict["AWS_CREDENTIAL_EXPIRATION"] { credential["Expiration"] = v }
  guard let data = try? JSONSerialization.data(withJSONObject: credential, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8) else {
    fputs("Failed to serialize JSON\n", stderr)
    return 1
  }
  print(json)
  return 0
}

func cmdExec(args: ArraySlice<String>) -> Int32 {
  var argv = Array(args)
  if argv.count < 2 { abortWithHelp() }
  let namespaceArg = argv[0]
  argv.removeFirst()
  let namespaces = namespaceArg.split(separator: ",").map(String.init)
  for name in namespaces {
    guard isValidNamespace(name) else {
      fputs("Invalid namespace name: \(name)\n", stderr)
      return 1
    }
    let found = Keychain.searchValues(namespace: name) { key, value in
      guard isValidEnvKey(key) else {
        fputs("WARNING: skipping invalid key \"\(key)\" in namespace `\(name)`\n", stderr)
        return
      }
      setenv(key, value, 1)
    }
    if !found {
      fputs("WARNING: namespace `\(name)` not defined.\n", stderr)
      fputs("     You can set via running `\(CommandLine.arguments[0]) --set \(name) SOME_ENV_NAME`.\n\n", stderr)
    }
  }
  let exe = argv[0]
  var cArgs: [UnsafeMutablePointer<CChar>?] = []
  for arg in argv {
    guard let dup = strdup(arg) else {
      for ptr in cArgs { free(ptr) }
      fputs("Out of memory\n", stderr)
      return 1
    }
    cArgs.append(dup)
  }
  cArgs.append(nil)
  execvp(exe, &cArgs)
  let err = String(cString: strerror(errno))
  for ptr in cArgs { free(ptr) }
  fputs("execvp failed: \(err)\n", stderr)
  return 1
}

// MARK: - Input Helpers

nonisolated(unsafe) private var savedTermios: termios?

private func restoreTerminal(_: Int32) {
  if var attrs = savedTermios {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &attrs)
  }
  let nl: [UInt8] = [0x0A]
  nl.withUnsafeBufferPointer { _ = write(STDOUT_FILENO, $0.baseAddress!, 1) }
  _exit(130)
}

func noechoRead(prompt: String) -> String? {
  var oldAttrs = termios()
  guard tcgetattr(STDIN_FILENO, &oldAttrs) == 0 else {
    if errno == ENOTTY {
      fputs("--noecho (-n) requires stdin to be a terminal\n", stderr)
    } else {
      fputs("oops when attempted to read: \(String(cString: strerror(errno)))\n", stderr)
    }
    return nil
  }
  var newAttrs = oldAttrs
  newAttrs.c_lflag &= ~tcflag_t(ECHO)
  guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &newAttrs) == 0 else {
    fputs("tcsetattr failed\n", stderr)
    exit(10)
  }
  savedTermios = oldAttrs
  signal(SIGINT, restoreTerminal)
  signal(SIGTERM, restoreTerminal)
  fputs("\(prompt) (noecho):", stdout)
  fflush(stdout)
  let input = readLine()
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &oldAttrs)
  savedTermios = nil
  signal(SIGINT, SIG_DFL)
  signal(SIGTERM, SIG_DFL)
  fputs("\n", stdout)
  return input
}

func askValue(name: String, key: String, noecho: Bool) -> String? {
  let prompt = "\(name).\(key)"
  if noecho {
    return noechoRead(prompt: prompt)
  } else {
    fputs("\(prompt): ", stdout)
    fflush(stdout)
    return readLine()
  }
}
