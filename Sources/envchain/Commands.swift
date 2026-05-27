import ArgumentParser
import Foundation

private func warnNamespaceNotDefined(_ namespace: String) {
  print("WARNING: namespace `\(namespace)` not defined.", to: &stdError)
  print(
    "     You can set via running `envchain set \(namespace) SOME_ENV_NAME`.\n",
    to: &stdError)
}

// MARK: - Set

extension Envchain {
  struct Set: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Add keychain items for a namespace"
    )

    @Flag(
      name: [.short, .customLong("noecho")],
      help: "Do not echo input when prompting")
    var noecho = false

    @Flag(
      name: [.customShort("p"), .customLong("require-passphrase")],
      help: "Require authentication to access the item")
    var requirePassphrase = false

    @Flag(
      name: [.customShort("P"), .customLong("no-require-passphrase")],
      help: "Do not require authentication")
    var noRequirePassphrase = false

    @Argument(help: "The namespace to store variables in")
    var namespace: String

    @Argument(help: "Environment variable names to set")
    var keys: [String]

    mutating func run() throws {
      let backend = currentBackend()
      let passphrase: Int =
        requirePassphrase ? 1 : (noRequirePassphrase ? 0 : -1)
      for key in keys {
        guard let value = askValue(name: namespace, key: key, noecho: noecho)
        else {
          throw ExitCode(1)
        }
        try backend.saveValue(
          namespace: namespace, key: key, value: value,
          requirePassphrase: passphrase)
      }
    }
  }
}

// MARK: - List

extension Envchain {
  struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List namespaces or keys in a namespace"
    )

    @Flag(
      name: [.customShort("v"), .customLong("show-value")],
      help: "Show values alongside keys")
    var showValue = false

    @Argument(help: "Namespace to list keys for (omit to list all namespaces)")
    var namespace: String?

    mutating func validate() throws {
      if namespace == nil && showValue {
        throw ValidationError("--show-value requires a namespace argument")
      }
    }

    mutating func run() throws {
      let backend = currentBackend()
      if let namespace = namespace {
        let result = try backend.searchValues(namespace: namespace)
        if result.found {
          for (key, value) in result.values.sorted(by: { $0.key < $1.key }) {
            if showValue {
              print("\(key)=\(value)")
            } else {
              print(key)
            }
          }
        } else {
          warnNamespaceNotDefined(namespace)
        }
      } else {
        let namespaces = try backend.searchNamespaces()
        for ns in namespaces {
          print(ns)
        }
      }
    }
  }
}

// MARK: - Unset

extension Envchain {
  struct Unset: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Remove keychain items from a namespace"
    )

    @Argument(help: "The namespace to remove variables from")
    var namespace: String

    @Argument(help: "Environment variable names to remove")
    var keys: [String]

    mutating func run() throws {
      let backend = currentBackend()
      for key in keys {
        try backend.deleteValue(namespace: namespace, key: key)
      }
    }
  }
}

// MARK: - JSON

extension Envchain {
  struct JSON: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Print all values in a namespace as JSON"
    )

    @Argument(help: "The namespace to print")
    var namespace: String

    mutating func run() throws {
      let backend = currentBackend()
      let result = try backend.searchValues(namespace: namespace)
      if !result.found {
        warnNamespaceNotDefined(namespace)
        throw ExitCode(1)
      }
      guard
        let data = try? JSONSerialization.data(
          withJSONObject: result.values, options: [.sortedKeys]),
        let json = String(data: data, encoding: .utf8)
      else {
        throw ValidationError("Failed to serialize JSON")
      }
      print(json)
    }
  }
}

// MARK: - AWS Credential

extension Envchain {
  struct AWSCredential: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "aws-credential",
      abstract: "Output AWS credential_process JSON format"
    )

    @Argument(help: "The namespace containing AWS credentials")
    var namespace: String

    mutating func run() throws {
      let backend = currentBackend()
      let result = try backend.searchValues(namespace: namespace)
      if !result.found {
        warnNamespaceNotDefined(namespace)
        throw ExitCode(1)
      }
      var credential: [String: Any] = ["Version": 1]
      if let v = result.values["AWS_ACCESS_KEY_ID"] {
        credential["AccessKeyId"] = v
      }
      if let v = result.values["AWS_SECRET_ACCESS_KEY"] {
        credential["SecretAccessKey"] = v
      }
      if let v = result.values["AWS_SESSION_TOKEN"] {
        credential["SessionToken"] = v
      }
      if let v = result.values["AWS_CREDENTIAL_EXPIRATION"] {
        credential["Expiration"] = v
      }
      guard
        let data = try? JSONSerialization.data(
          withJSONObject: credential, options: [.sortedKeys]),
        let json = String(data: data, encoding: .utf8)
      else {
        throw ValidationError("Failed to serialize JSON")
      }
      print(json)
    }
  }
}

// MARK: - Exec

extension Envchain {
  struct Exec: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Execute a command with environment variables from namespaces"
    )

    @Argument(
      help: "Namespace(s) to load (comma-separated)",
      transform: { $0.split(separator: ",").map(String.init) })
    var namespaces: [String]

    @Argument(
      parsing: .captureForPassthrough,
      help: "Command and arguments to execute")
    var command: [String]

    mutating func validate() throws {
      guard !command.isEmpty else {
        throw ValidationError("A command is required")
      }
    }

    mutating func run() throws {
      let backend = currentBackend()
      for name in namespaces {
        let result = try backend.searchValues(namespace: name)
        if result.found {
          for (key, value) in result.values {
            guard isValidEnvKey(key) else {
              print(
                "WARNING: skipping invalid key \"\(key)\" in namespace `\(name)`",
                to: &stdError)
              continue
            }
            setenv(key, value, 1)
          }
        } else {
          warnNamespaceNotDefined(name)
        }
      }
      // Build a null-terminated C string array for execvp.
      // Memory from strdup is intentionally never freed —
      // execvp replaces the process on success,
      // and _exit terminates immediately on failure.
      var cArgs = command.map { strdup($0) } + [nil]
      execvp(cArgs[0]!, &cArgs)
      // execvp only returns on failure
      perror(command[0])
      // Use _exit (not exit/throw) to terminate immediately
      // without running Swift deinitializers, atexit handlers,
      // or flushing buffers that may contain secret values
      // loaded into the environment above.
      _exit(127)
    }
  }
}

// MARK: - Input Helpers

nonisolated(unsafe) private var savedTermios: termios?

func askValue(name: String, key: String, noecho: Bool) -> String? {
  let prompt = "\(name).\(key)"
  if noecho {
    return noechoRead(prompt: prompt)
  } else {
    print("\(prompt): ", terminator: "", to: &stdError)
    return readLine()
  }
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

private func restoreTerminal(_: Int32) {
  if var attrs = savedTermios {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &attrs)
  }
  let nl: [UInt8] = [0x0A]
  nl.withUnsafeBufferPointer { _ = write(STDERR_FILENO, $0.baseAddress!, 1) }
  _exit(130)
}
