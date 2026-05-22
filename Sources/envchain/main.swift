import Foundation
import Security
import Darwin

private let servicePrefix = "envchain-"

// MARK: - Keychain Operations

struct Keychain {
    static func serviceName(for namespace: String) -> String {
        return "\(servicePrefix)\(namespace)"
    }

    static func saveValue(namespace: String, key: String, value: String, requirePassphrase: Int) {
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
            let update: [String: Any] = [kSecValueData as String: valueData]
            status = SecItemUpdate(searchQuery as CFDictionary, update as CFDictionary)
        } else {
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
            }
            status = SecItemAdd(newItem as CFDictionary, nil)
        }
        if status != errSecSuccess {
            failWithOSStatus(status)
        }
    }

    static func searchValues(namespace: String, callback: (String, String) -> Void) -> Bool {
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
            let valueStatus = SecItemCopyMatching(valueQuery as CFDictionary, &valueResult)
            guard valueStatus == errSecSuccess,
                  let data = valueResult as? Data,
                  let value = String(data: data, encoding: .utf8) else {
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
               service.hasPrefix(servicePrefix) {
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
            fputs("Error: \(msg)\n", stderr)
        } else {
            fputs("Error: \(status)\n", stderr)
        }
        exit(10)
    }
}

// MARK: - Input

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
    newAttrs.c_lflag &= ~UInt(ECHO)
    guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &newAttrs) == 0 else {
        fputs("tcsetattr failed\n", stderr)
        exit(10)
    }
    fputs("\(prompt) (noecho):", stdout)
    fflush(stdout)
    let input = readLine()
    if tcsetattr(STDIN_FILENO, TCSAFLUSH, &oldAttrs) != 0 {
        fputs("tcsetattr restore failed\n", stderr)
        exit(10)
    }
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

// MARK: - Help

func abortWithHelp() -> Never {
    let name = CommandLine.arguments[0]
    fputs("""
        \(name) version \(version)

        Usage:
          Add variables
            \(name) (--set|-s) [--[no-]require-passphrase|-p|-P] [--noecho|-n] NAMESPACE ENV [ENV ..]
          Execute with variables
            \(name) NAMESPACE CMD [ARG ...]
          Print as JSON
            \(name) --json NAMESPACE
          AWS credential_process
            \(name) --aws-credential NAMESPACE
          List namespaces
            \(name) --list
          Remove variables
            \(name) --unset NAMESPACE ENV [ENV ..]

        Options:
          --set (-s):
            Add keychain item of environment variable +ENV+ for namespace +NAMESPACE+.

          --noecho (-n):
            Enable noecho mode when prompting values. Requires stdin to be a terminal.

          --require-passphrase (-p), --no-require-passphrase (-P):
            Replace the item's ACL list to require passphrase (or not).
            Leave as is when both options are omitted.

        """, stderr)
    exit(2)
}

// MARK: - Commands

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
    argv.removeFirst()
    for key in argv {
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
        let found = Keychain.searchValues(namespace: target) { key, value in
            if showValue {
                print("\(key)=\(value)")
            } else {
                print(key)
            }
        }
        if !found {
            fputs("WARNING: namespace `\(target)` not defined.\n", stderr)
            fputs("         You can set via running `\(CommandLine.arguments[0]) --set \(target) SOME_ENV_NAME`.\n\n", stderr)
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
    var dict: [String: String] = [:]
    let found = Keychain.searchValues(namespace: name) { key, value in
        dict[key] = value
    }
    if !found {
        fputs("WARNING: namespace `\(name)` not defined.\n", stderr)
        fputs("         You can set via running `\(CommandLine.arguments[0]) --set \(name) SOME_ENV_NAME`.\n\n", stderr)
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
    var dict: [String: String] = [:]
    let found = Keychain.searchValues(namespace: name) { key, value in
        dict[key] = value
    }
    if !found {
        fputs("WARNING: namespace `\(name)` not defined.\n", stderr)
        fputs("         You can set via running `\(CommandLine.arguments[0]) --set \(name) SOME_ENV_NAME`.\n\n", stderr)
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
        let found = Keychain.searchValues(namespace: name) { key, value in
            setenv(key, value, 1)
        }
        if !found {
            fputs("WARNING: namespace `\(name)` not defined.\n", stderr)
            fputs("         You can set via running `\(CommandLine.arguments[0]) --set \(name) SOME_ENV_NAME`.\n\n", stderr)
        }
    }
    let exe = argv[0]
    let cArgs = argv.map { strdup($0)! }
    var cArgsWithNull = cArgs + [nil]
    execvp(exe, &cArgsWithNull)
    fputs("execvp failed: \(String(cString: strerror(errno)))\n", stderr)
    return 1
}

// MARK: - Entry Point

func main() -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty { abortWithHelp() }
    if args[0] == "--set" || args[0] == "-s" {
        args.removeFirst()
        return cmdSet(args: args[...])
    } else if args[0] == "--list" || args[0] == "-l" {
        args.removeFirst()
        return cmdList(args: args[...])
    } else if args[0] == "--json" {
        args.removeFirst()
        return cmdJSON(args: args[...])
    } else if args[0] == "--aws-credential" {
        args.removeFirst()
        return cmdAWSCredential(args: args[...])
    } else if args[0] == "--unset" {
        args.removeFirst()
        return cmdUnset(args: args[...])
    } else if args[0].hasPrefix("-") {
        fputs("Unknown option \(args[0])\n", stderr)
        return 2
    } else {
        return cmdExec(args: args[...])
    }
}

exit(main())
