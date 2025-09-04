import ArgumentParser
import XcodeQueryCLI

@main
struct XcodeQueryMainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [QueryCommand.self, SchemaCommand.self],
        defaultSubcommand: QueryCommand.self
    )
}
