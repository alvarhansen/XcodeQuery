import Foundation
import XcodeQueryKit

@main
struct XcodeQueryWasmMain {
    static func main() {}
}

@MainActor
private var lastErrorMessage: String?

@_cdecl("xcq_free")
public func xcq_free(_ pointer: UnsafeMutablePointer<CChar>?) {
    guard let pointer else {
        return
    }
    pointer.deallocate()
}

@MainActor
@_cdecl("xcq_alloc")
public func xcq_alloc(_ size: Int) -> UnsafeMutablePointer<CChar>? {
    guard size > 0 else {
        return nil
    }
    return UnsafeMutablePointer<CChar>.allocate(capacity: size)
}

@MainActor
@_cdecl("xcq_last_error")
public func xcq_last_error() -> UnsafeMutablePointer<CChar>? {
    guard let message = lastErrorMessage else {
        return nil
    }
    return makeCString(message)
}

@MainActor
@_cdecl("xcq_query_from_pbxproj_json")
public func xcq_query_from_pbxproj_json(
    _ dataPointer: UnsafePointer<UInt8>?,
    _ length: Int,
    _ queryPointer: UnsafePointer<UInt8>?,
    _ queryLength: Int,
    _ projectPathPointer: UnsafePointer<UInt8>?,
    _ projectPathLength: Int
) -> UnsafeMutablePointer<CChar>? {
    guard let dataPointer, length > 0 else {
        lastErrorMessage = "pbxproj bytes are required"
        return nil
    }
    guard let queryPointer, queryLength > 0 else {
        lastErrorMessage = "query bytes are required"
        return nil
    }

    let pbxprojData = Data(bytes: dataPointer, count: length)
    guard let query = decodeUTF8(pointer: queryPointer, length: queryLength) else {
        lastErrorMessage = "query is not valid UTF-8"
        return nil
    }

    var projectPath: String? = nil
    if let projectPathPointer, projectPathLength > 0 {
        projectPath = decodeUTF8(pointer: projectPathPointer, length: projectPathLength)
        if projectPath == nil {
            lastErrorMessage = "project path is not valid UTF-8"
            return nil
        }
    }

    do {
        let result = try XcodeProjectQuery.evaluate(query: query, pbxprojData: pbxprojData, projectPath: projectPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(result)
        lastErrorMessage = nil
        return makeCString(String(decoding: json, as: UTF8.self))
    } catch {
        lastErrorMessage = errorMessage(error)
        return nil
    }
}

private func makeCString(_ string: String) -> UnsafeMutablePointer<CChar>? {
    let bytes = Array(string.utf8CString)
    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
    buffer.initialize(from: bytes, count: bytes.count)
    return buffer
}

private func decodeUTF8(pointer: UnsafePointer<UInt8>, length: Int) -> String? {
    guard length > 0 else {
        return ""
    }
    let data = Data(bytes: pointer, count: length)
    return String(data: data, encoding: .utf8)
}

private func errorMessage(_ error: Error) -> String {
    if case let XcodeProjectQuery.Error.invalidQuery(message) = error {
        return message
    }
    if let gqlError = error as? GraphQLError {
        return gqlError.message
    }
    if let localized = (error as? LocalizedError)?.errorDescription {
        return localized
    }
    return (error as NSError).localizedDescription
}
