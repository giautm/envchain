import Foundation

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
