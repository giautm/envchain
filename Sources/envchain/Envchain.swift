import ArgumentParser
import Foundation

struct StderrOutputStream: TextOutputStream {
  mutating func write(_ string: String) {
    FileHandle.standardError.write(Data(string.utf8))
  }
}
nonisolated(unsafe) var stdError = StderrOutputStream()

@main
struct Envchain: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "envchain",
    abstract: "Set environment variables from macOS Keychain",
    version: version,
    subcommands: [
      Exec.self,
      Set.self,
      Unset.self,
      List.self,
      JSON.self,
      AWSCredential.self,
    ],
    defaultSubcommand: Exec.self
  )

  public static func main() {
    // Disable core dumps to prevent secrets from being written to disk
    var rl = rlimit(rlim_cur: 0, rlim_max: 0)
    #if os(Linux)
    setrlimit(Int32(RLIMIT_CORE.rawValue), &rl)
    #else
    setrlimit(RLIMIT_CORE, &rl)
    #endif
    // Rewrite flag-style arguments to subcommands (sorah/envchain compatibility)
    let args = Array(CommandLine.arguments.dropFirst())
    let rewritten = rewriteFlagArgs(args)
    Self.main(rewritten)
  }

  /// Maps `--set`, `--list`, `--unset`, `--json`, `--aws-credential`
  /// flags to their subcommand equivalents for sorah/envchain compatibility.
  private static func rewriteFlagArgs(_ args: [String]) -> [String]? {
    guard let first = args.first else {
      return args
    }
    let flagMap: [String: String] = [
      "--set": "set",
      "--list": "list",
      "--unset": "unset",
      "--json": "json",
      "--aws-credential": "aws-credential",
    ]
    if let subcommand = flagMap[first] {
      return [subcommand] + Array(args.dropFirst())
    }
    return args
  }
}
