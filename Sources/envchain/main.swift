@preconcurrency import Foundation

struct StderrOutputStream: TextOutputStream {
  mutating func write(_ string: String) {
    FileHandle.standardError.write(Data(string.utf8))
  }
}
nonisolated(unsafe) var stdError = StderrOutputStream()

// Disable core dumps to prevent secrets from being written to disk
var rl = rlimit(rlim_cur: 0, rlim_max: 0)
#if os(Linux)
setrlimit(Int32(RLIMIT_CORE.rawValue), &rl)
#else
setrlimit(RLIMIT_CORE, &rl)
#endif

func printHelp() {
  let name = CommandLine.arguments[0]
  print(
    """
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

    """, to: &stdError)
}

func main() -> Int32 {
  var args = Array(CommandLine.arguments.dropFirst())
  if args.isEmpty {
    printHelp()
    return 2
  }
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
    print("Unknown option \(args[0])", to: &stdError)
    return 2
  } else {
    return cmdExec(args: args[...])
  }
}

exit(main())
