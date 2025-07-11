import XcodeProj

public class XcodeProjectQuery {
    
    public enum Error: Swift.Error {
        case invalidQuery(String)
    }
    
    private let projectPath: String
    
    public init(projectPath: String) {
        self.projectPath = projectPath
    }
    
    public func evaluate(query: String) throws -> Encodable {
        let proj = try XcodeProj(pathString: projectPath)
        
        switch query {
            case ".targets":
            let result = proj.pbxproj.nativeTargets.map { pbxNativeTarget in
                Target(name: pbxNativeTarget.name)
            }
//            print(result)
            return result
        default:
            throw Error.invalidQuery(query)
        }
    }
}

struct Target: Encodable {
    var name: String
}
