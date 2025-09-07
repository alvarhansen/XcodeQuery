import ArgumentParser
import XcodeQueryCLI

@main
struct XcodeQueryMainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcq",
        subcommands: [QueryCommand.self, SchemaCommand.self],
        defaultSubcommand: QueryCommand.self
    )
}
