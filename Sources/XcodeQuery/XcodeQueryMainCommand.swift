import ArgumentParser
import XcodeQueryCLI

@main
struct XcodeQueryMainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcq",
        subcommands: [QueryCommand.self, SchemaCommand.self, InteractiveCommand.self, InteractiveAliasCommand.self],
        defaultSubcommand: QueryCommand.self
    )
}
