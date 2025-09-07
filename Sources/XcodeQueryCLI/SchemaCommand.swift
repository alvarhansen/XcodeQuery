import Foundation
import ArgumentParser
import Darwin

public struct SchemaCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Print the GraphQL-style query schema summary"
    )

    @Flag(name: .customLong("no-color"), help: "Disable ANSI colors in schema output")
    var noColor: Bool = false
    @Flag(name: .customLong("color"), help: "Force ANSI colors in schema output")
    var yesColor: Bool = false

    public init() {}

    public func run() async throws {
        let env = ProcessInfo.processInfo.environment
        let force = env["XCQ_FORCE_COLOR"] == "1" || env["FORCE_COLOR"] == "1"
        let enableColor = noColor ? false : (yesColor || force || isatty(STDOUT_FILENO) == 1)
        print(Self.renderSchema(color: enableColor))
    }

    // MARK: - Pretty schema renderer
    private struct C {
        let enabled: Bool
        let reset = "\u{001B}[0m"
        let bold = "\u{001B}[1m"
        let dim = "\u{001B}[2m"
        let green = "\u{001B}[32m"
        let yellow = "\u{001B}[33m"
        let blue = "\u{001B}[34m"
        let magenta = "\u{001B}[35m"
        let cyan = "\u{001B}[36m"
        func s(_ s: String, _ color: String) -> String { enabled ? color + s + reset : s }
        func b(_ s: String) -> String { enabled ? bold + s + reset : s }
        func d(_ s: String) -> String { enabled ? dim + s + reset : s }
    }

    private static func renderSchema(color: Bool) -> String {
        let Cx = C(enabled: color)
        var out: [String] = []
        out.append("")
        out.append(Cx.b(Cx.s("XcodeQuery GraphQL Schema", Cx.cyan)))
        out.append("")

        // Top-level fields
        out.append(Cx.b("Top-level fields (selection required):"))
        func fn(_ name: String, _ args: String, _ ret: String) -> String {
            "- " + Cx.s(name, Cx.green) + Cx.d("(") + args + Cx.d(")") + Cx.d(": ") + Cx.s(ret, Cx.cyan)
        }
        func arg(_ n: String, _ type: String, _ def: String? = nil) -> String {
            let base = Cx.s(n + ":", Cx.yellow) + " " + Cx.s(type, Cx.cyan)
            if let d = def { return base + Cx.d(" = ") + Cx.s(d, Cx.magenta) } else { return base }
        }
        let aTargets = [arg("type", "TargetType"), arg("filter", "TargetFilter")].joined(separator: Cx.d(", "))
        out.append(fn("targets", aTargets, "[Target!]!"))
        out.append(fn("target", arg("name", "String!"), "Target"))
        let aDeps = [arg("name", "String!"), arg("recursive", "Boolean", "false"), arg("filter", "TargetFilter")].joined(separator: Cx.d(", "))
        out.append(fn("dependencies", aDeps, "[Target!]!"))
        out.append(fn("dependents", aDeps, "[Target!]!"))
        let aPathFilter = [arg("pathMode", "PathMode", "FILE_REF"), arg("filter", "SourceFilter")].joined(separator: Cx.d(", "))
        out.append(fn("targetSources", aPathFilter, "[TargetSource!]!"))
        let aResFilter = [arg("pathMode", "PathMode", "FILE_REF"), arg("filter", "ResourceFilter")].joined(separator: Cx.d(", "))
        out.append(fn("targetResources", aResFilter, "[TargetResource!]!"))
        out.append(fn("targetDependencies", [arg("recursive", "Boolean", "false"), arg("filter", "TargetFilter")].joined(separator: Cx.d(", ")), "[TargetDependency!]!"))
        out.append(fn("targetBuildScripts", arg("filter", "BuildScriptFilter"), "[TargetBuildScript!]!"))
        out.append(fn("targetMembership", [arg("path", "String!"), arg("pathMode", "PathMode", "FILE_REF")].joined(separator: Cx.d(", ")), "TargetMembership!"))
        out.append("")

        // Types
        out.append(Cx.b("Types:"))
        func field(_ n: String, _ t: String) -> String { "    " + Cx.s(n + ":", Cx.yellow) + " " + Cx.s(t, Cx.cyan) }
        func appendType(_ name: String, _ fields: [String]) {
            out.append("- " + Cx.s("type", Cx.blue) + " " + Cx.s(name, Cx.cyan) + " {")
            for f in fields { out.append(f) }
            out.append("  }")
        }
        out.append("- " + Cx.s("type", Cx.blue) + " " + Cx.s("Target", Cx.cyan) + " {")
        out.append(field("name", "String!") )
        out.append(field("type", "TargetType!") )
        out.append("    " + Cx.s("dependencies", Cx.green) + Cx.d("(") + [arg("recursive", "Boolean", "false"), arg("filter", "TargetFilter")].joined(separator: Cx.d(", ")) + Cx.d("):") + " " + Cx.s("[Target!]!", Cx.cyan))
        out.append("    " + Cx.s("sources", Cx.green) + Cx.d("(") + [arg("pathMode", "PathMode", "FILE_REF"), arg("filter", "SourceFilter")].joined(separator: Cx.d(", ")) + Cx.d("):") + " " + Cx.s("[Source!]!", Cx.cyan))
        out.append("    " + Cx.s("resources", Cx.green) + Cx.d("(") + [arg("pathMode", "PathMode", "FILE_REF"), arg("filter", "ResourceFilter")].joined(separator: Cx.d(", ")) + Cx.d("):") + " " + Cx.s("[Resource!]!", Cx.cyan))
        out.append("    " + Cx.s("buildScripts", Cx.green) + Cx.d("(") + arg("filter", "BuildScriptFilter") + Cx.d("):") + " " + Cx.s("[BuildScript!]!", Cx.cyan))
        out.append("  }")
        appendType("Source", [field("path", "String!")])
        appendType("Resource", [field("path", "String!")])
        appendType("BuildScript", [
            field("name", "String"),
            field("stage", "ScriptStage!"),
            field("inputPaths", "[String!]!"),
            field("outputPaths", "[String!]!"),
            field("inputFileListPaths", "[String!]!"),
            field("outputFileListPaths", "[String!]!")
        ])
        appendType("TargetSource", [field("target", "String!"), field("path", "String!")])
        appendType("TargetResource", [field("target", "String!"), field("path", "String!")])
        appendType("TargetDependency", [field("target", "String!"), field("name", "String!"), field("type", "TargetType!")])
        appendType("TargetBuildScript", [field("target", "String!"), field("name", "String"), field("stage", "ScriptStage!"), field("inputPaths", "[String!]!"), field("outputPaths", "[String!]!"), field("inputFileListPaths", "[String!]!"), field("outputFileListPaths", "[String!]!")])
        appendType("TargetMembership", [field("path", "String!"), field("targets", "[String!]")])
        out.append("")

        // Enums
        out.append(Cx.b("Enums:"))
        out.append("- " + Cx.s("enum", Cx.blue) + " " + Cx.s("TargetType", Cx.cyan) + " { " + Cx.s("APP, FRAMEWORK, STATIC_LIBRARY, DYNAMIC_LIBRARY, UNIT_TEST, UI_TEST, EXTENSION, BUNDLE, COMMAND_LINE_TOOL, WATCH_APP, WATCH2_APP, TV_APP, OTHER", Cx.magenta) + " }")
        out.append("- " + Cx.s("enum", Cx.blue) + " " + Cx.s("PathMode", Cx.cyan) + " { " + Cx.s("FILE_REF, ABSOLUTE, NORMALIZED", Cx.magenta) + " }")
        out.append("- " + Cx.s("enum", Cx.blue) + " " + Cx.s("ScriptStage", Cx.cyan) + " { " + Cx.s("PRE, POST", Cx.magenta) + " }")
        out.append("")

        // Filters
        out.append(Cx.b("Filters:"))
        out.append("- " + Cx.s("input", Cx.blue) + " " + Cx.s("StringMatch", Cx.cyan) + " { " + [Cx.s("eq", Cx.yellow) + ": String", Cx.s("regex", Cx.yellow) + ": String", Cx.s("prefix", Cx.yellow) + ": String", Cx.s("suffix", Cx.yellow) + ": String", Cx.s("contains", Cx.yellow) + ": String"].joined(separator: ", ") + " }")
        out.append("- " + Cx.s("input", Cx.blue) + " " + Cx.s("TargetFilter", Cx.cyan) + " { " + [Cx.s("name", Cx.yellow) + ": StringMatch", Cx.s("type", Cx.yellow) + ": TargetType"].joined(separator: ", ") + " }")
        out.append("- " + Cx.s("input", Cx.blue) + " " + Cx.s("SourceFilter", Cx.cyan) + " { " + [Cx.s("path", Cx.yellow) + ": StringMatch", Cx.s("target", Cx.yellow) + ": StringMatch"].joined(separator: ", ") + " }")
        out.append("- " + Cx.s("input", Cx.blue) + " " + Cx.s("ResourceFilter", Cx.cyan) + " { " + [Cx.s("path", Cx.yellow) + ": StringMatch", Cx.s("target", Cx.yellow) + ": StringMatch"].joined(separator: ", ") + " }")
        out.append("- " + Cx.s("input", Cx.blue) + " " + Cx.s("BuildScriptFilter", Cx.cyan) + " { " + [Cx.s("stage", Cx.yellow) + ": ScriptStage", Cx.s("name", Cx.yellow) + ": StringMatch", Cx.s("target", Cx.yellow) + ": StringMatch"].joined(separator: ", ") + " }")
        out.append("")

        // Examples
        out.append(Cx.b("Examples:"))
        func br(_ s: String) -> String { Cx.d(s) }
        // 1) { targets { name type } }
        out.append("- " + br("{") + " " + Cx.s("targets", Cx.green) + " " + br("{") + " " + Cx.s("name", Cx.green) + " " + Cx.s("type", Cx.green) + " " + br("}") + " " + br("}"))
        // 2) { dependencies(name: "App") { name } }
        out.append("- " + br("{") + " " + Cx.s("dependencies", Cx.green) + br("(") + Cx.s("name:", Cx.yellow) + " " + Cx.s("\"App\"", Cx.magenta) + br(")") + " " + br("{") + " " + Cx.s("name", Cx.green) + " " + br("}") + " " + br("}"))
        // 3) { targets(type: UNIT_TEST) { dependencies(recursive: true) { name } } }
        out.append("- " + br("{") + " " + Cx.s("targets", Cx.green) + br("(") + Cx.s("type:", Cx.yellow) + " " + Cx.s("UNIT_TEST", Cx.magenta) + br(")") + " " + br("{") + " " + Cx.s("dependencies", Cx.green) + br("(") + Cx.s("recursive:", Cx.yellow) + " true" + br(")") + " " + br("{") + " " + Cx.s("name", Cx.green) + " " + br("}") + " " + br("}") + " " + br("}"))
        // 4) { targetSources(pathMode: NORMALIZED) { target path } }
        out.append("- " + br("{") + " " + Cx.s("targetSources", Cx.green) + br("(") + Cx.s("pathMode:", Cx.yellow) + " " + Cx.s("NORMALIZED", Cx.magenta) + br(")") + " " + br("{") + " " + Cx.s("target", Cx.green) + " " + Cx.s("path", Cx.green) + " " + br("}") + " " + br("}"))
        // 5) { targetMembership(path: "Shared/Shared.swift", pathMode: NORMALIZED) { path targets } }
        out.append("- " + br("{") + " " + Cx.s("targetMembership", Cx.green) + br("(") + Cx.s("path:", Cx.yellow) + " " + Cx.s("\"Shared/Shared.swift\"", Cx.magenta) + Cx.d(", ") + Cx.s("pathMode:", Cx.yellow) + " " + Cx.s("NORMALIZED", Cx.magenta) + br(")") + " " + br("{") + " " + Cx.s("path", Cx.green) + " " + Cx.s("targets", Cx.green) + " " + br("}") + " " + br("}"))
        // 6) { targetBuildScripts(filter: { stage: PRE }) { target name stage } }
        out.append("- " + br("{") + " " + Cx.s("targetBuildScripts", Cx.green) + br("(") + Cx.s("filter:", Cx.yellow) + " " + br("{") + " " + Cx.s("stage:", Cx.yellow) + " " + Cx.s("PRE", Cx.magenta) + " " + br("}") + br(")") + " " + br("{") + " " + Cx.s("target", Cx.green) + " " + Cx.s("name", Cx.green) + " " + Cx.s("stage", Cx.green) + " " + br("}") + " " + br("}"))
        out.append("")
        return out.joined(separator: "\n")
    }

    // Test hook
    static func __test_renderSchema(useColor: Bool) -> String { renderSchema(color: useColor) }
}
