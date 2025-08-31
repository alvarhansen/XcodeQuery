import XcodeProj

public class XcodeProjectQuery {
    
    public enum Error: Swift.Error {
        case invalidQuery(String)
    }
    
    private let projectPath: String
    
    public init(projectPath: String) {
        self.projectPath = projectPath
    }
    
    public func evaluate(query: String) throws -> AnyEncodable {
        let proj = try XcodeProj(pathString: projectPath)

        // Build base targets model
        let targets: [Target] = proj.pbxproj.nativeTargets.map { t in
            Target(name: t.name, type: TargetType.from(productType: t.productType))
        }

        // Support queries:
        // - .targets
        // - .targets[]
        // - .targets[] | filter(.name.hasSuffix("Tests"))
        // - .targets[] | filter(.name | hasSuffix("Tests"))
        // - .targets[] | filter(.type == .unitTest)
        if query == ".targets" || query == ".targets[]" {
            return AnyEncodable(targets)
        }

        if let pred = Self.extractFilterPredicate(from: query) {
            let filtered = try Self.apply(predicate: pred, to: targets)
            return AnyEncodable(filtered)
        }

        throw Error.invalidQuery(query)
    }
}

struct Target: Codable {
    var name: String
    var type: TargetType
}

enum TargetType: String, Codable, Equatable {
    case app
    case framework
    case staticLibrary
    case dynamicLibrary
    case unitTest
    case uiTest
    case extensionKit
    case bundle
    case commandLineTool
    case watchApp
    case watch2App
    case tvApp
    case other

    static func from(productType: PBXProductType?) -> TargetType {
        guard let productType else { return .other }
        switch productType {
        case .application: return .app
        case .framework: return .framework
        case .staticLibrary: return .staticLibrary
        case .dynamicLibrary: return .dynamicLibrary
        case .unitTestBundle: return .unitTest
        case .uiTestBundle: return .uiTest
        case .appExtension: return .extensionKit
        case .bundle: return .bundle
        case .commandLineTool: return .commandLineTool
        case .watchApp: return .watchApp
        case .watch2App: return .watch2App
        default:
            return .other
        }
    }
}

public struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    public init<T: Encodable>(_ wrapped: T) {
        self._encode = wrapped.encode
    }

    public func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - Simple query parsing

extension XcodeProjectQuery {
    private static func extractFilterPredicate(from query: String) -> String? {
        // Accept forms like: ".targets[] | filter(<predicate>)"
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(".targets[]") else { return nil }
        let remainder = trimmed.dropFirst(".targets[]".count).trimmingCharacters(in: .whitespaces)
        guard remainder.hasPrefix("| filter(") && remainder.hasSuffix(")") else { return nil }
        let start = remainder.index(remainder.startIndex, offsetBy: 2) // skip "| "
        let call = remainder[start...]
        guard call.hasPrefix("filter(") && call.last == ")" else { return nil }
        let inner = call.dropFirst("filter(".count).dropLast()
        return String(inner).trimmingCharacters(in: .whitespaces)
    }

    private static func apply(predicate: String, to targets: [Target]) throws -> [Target] {
        // Support:
        // - .type == .unitTest
        // - .name.hasSuffix("Tests")
        // - .name | hasSuffix("Tests")
        if predicate.hasPrefix(".type == .") {
            let value = predicate.replacingOccurrences(of: ".type == .", with: "")
            if let t = TargetType(shortName: value) {
                return targets.filter { $0.type == t }
            }
        }

        if let suffix = extractHasSuffix(from: predicate) {
            return targets.filter { $0.name.hasSuffix(suffix) }
        }

        throw Error.invalidQuery(predicate)
    }

    private static func extractHasSuffix(from predicate: String) -> String? {
        // Matches ".name.hasSuffix("TEXT")" or ".name | hasSuffix("TEXT")"
        let trimmed = predicate.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(".name") else { return nil }
        let remainder = trimmed.dropFirst(".name".count).trimmingCharacters(in: .whitespaces)
        let callPart: Substring
        if remainder.hasPrefix("|") {
            // pipeline form: | hasSuffix("...")
            let afterPipe = remainder.dropFirst().trimmingCharacters(in: .whitespaces)
            callPart = Substring(afterPipe)
        } else if remainder.hasPrefix(".") {
            // dot-call form: .hasSuffix("...")
            callPart = remainder.dropFirst()
        } else {
            return nil
        }
        guard callPart.hasPrefix("hasSuffix(\"") && callPart.hasSuffix("\")") else { return nil }
        let inner = callPart.dropFirst("hasSuffix(\"".count).dropLast("\")".count)
        return String(inner)
    }
}

private extension TargetType {
    init?(shortName: String) {
        switch shortName {
        case "app": self = .app
        case "framework": self = .framework
        case "staticLibrary": self = .staticLibrary
        case "dynamicLibrary": self = .dynamicLibrary
        case "unitTest": self = .unitTest
        case "uiTest": self = .uiTest
        case "extension": self = .extensionKit
        case "bundle": self = .bundle
        case "commandLineTool": self = .commandLineTool
        case "watchApp": self = .watchApp
        case "watch2App": self = .watch2App
        case "tvApp": self = .tvApp
        default: return nil
        }
    }
}
