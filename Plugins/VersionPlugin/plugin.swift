import Foundation
import PackagePlugin

@main
struct VersionPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let output = context.pluginWorkDirectoryURL.appending(path: "Version.swift")
        return [
            .buildCommand(
                displayName: "Generate Version.swift",
                executable: try context.tool(named: "generate-version").url,
                arguments: [output.path()],
                outputFiles: [output]
            )
        ]
    }
}
