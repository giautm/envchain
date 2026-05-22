import Foundation

let output = CommandLine.arguments[1]
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
process.arguments = ["describe", "--tags", "--always"]
let pipe = Pipe()
process.standardOutput = pipe
process.standardError = FileHandle.nullDevice

var version = "dev"
do {
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus == 0,
       let data = try pipe.fileHandleForReading.readToEnd(),
       let tag = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
       !tag.isEmpty {
        version = tag
    }
} catch {}

let content = "let version = \"\(version)\"\n"
try content.write(toFile: output, atomically: true, encoding: .utf8)
