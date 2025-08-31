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
        
        switch query {
            case ".targets":
            let result = proj.pbxproj.nativeTargets.map { pbxNativeTarget in
                Target(name: pbxNativeTarget.name)
            }
            return AnyEncodable(result)
        default:
            throw Error.invalidQuery(query)
        }
    }
}

struct Target: Encodable {
    var name: String
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
