import XCTest
@testable import XcodeQueryKit

final class GraphQLBaselineSnapshotsTests: XCTestCase {
    struct SnapshotCase {
        let name: String
        let query: String
    }

    func testGraphQLOperatorSnapshots() throws {
        let query = """
        targetSources(pathMode: NORMALIZED, filter: { path: { prefix: \"Shared/\" } }) { target path }
        targetResources(filter: { path: { suffix: \"json\" } }) { target path }
        targetDependencies(filter: { name: { prefix: \"A\" } }) { target name type }
        """
        let fixture = try GraphQLBaselineFixture()
        var json = try fixture.evaluateToCanonicalJSON(query: query)
        // Normalize escaped slashes to match snapshot formatting
        json = json.replacingOccurrences(of: "\\/", with: "/")
        try GraphQLSnapshot.assertSnapshot(data: json, named: "operators", subdirectory: "GraphQLBaseline")
    }

    func testBuildScriptFilterSnapshots() throws {
        struct Case { let name: String; let query: String }
        let cases: [Case] = [
            Case(name: "buildscripts_pre", query: "targetBuildScripts(filter: { stage: PRE }) { target name stage }"),
            Case(name: "buildscripts_name_target", query: "targetBuildScripts(filter: { name: { contains: \"Pre\" }, target: { eq: \"App\" } }) { target name stage }")
        ]
        let fixture = try GraphQLBaselineFixture()
        for c in cases {
            let json = try fixture.evaluateToCanonicalJSON(query: c.query)
            try GraphQLSnapshot.assertSnapshot(data: json, named: c.name, subdirectory: "GraphQLBaseline")
        }
    }

    func testRegexFiltersSnapshots() throws {
        let query = """
        targetSources(pathMode: NORMALIZED, filter: { path: { regex: "\\.swift$" } }) { target path }
        targetResources(filter: { path: { regex: "json$" } }) { target path }
        """
        let fixture = try GraphQLBaselineFixture()
        var json = try fixture.evaluateToCanonicalJSON(query: query)
        json = json.replacingOccurrences(of: "\\/", with: "/")
        try GraphQLSnapshot.assertSnapshot(data: json, named: "regex_filters", subdirectory: "GraphQLBaseline")
    }

    func testBuildScriptsNestedPerTargetSnapshot() throws {
        let query = "targets { name buildScripts { name stage } }"
        let fixture = try GraphQLBaselineFixture()
        let json = try fixture.evaluateToCanonicalJSON(query: query)
        try GraphQLSnapshot.assertSnapshot(data: json, named: "buildscripts_nested", subdirectory: "GraphQLBaseline")
    }

    @MainActor
    func testGraphQLBaselineSnapshots() throws {
        let cases: [SnapshotCase] = [
            SnapshotCase(
                name: "baseline",
                query: """
                targets {
                    name
                    type
                    dependencies(recursive: true) { name type }
                    sources(pathMode: NORMALIZED) { path }
                    resources { path }
                    buildScripts { name stage inputPaths outputPaths }
                }
                target(name: \"App\") {
                    name
                    type
                    dependencies { name }
                }
                dependencies(name: \"App\", recursive: true) { name type }
                dependents(name: \"Lib\", recursive: true) { name type }
                targetSources(pathMode: NORMALIZED) { target path }
                targetResources(pathMode: NORMALIZED) { target path }
                targetDependencies(recursive: true) { target name type }
                targetBuildScripts { target name stage inputPaths outputPaths }
                targetMembership(path: \"Shared/Shared.swift\", pathMode: NORMALIZED) { path targets }
                """
            ),
            SnapshotCase(
                name: "filters",
                query: """
                targets(filter: { name: { suffix: \"Tests\" } }) { name type }
                targets(type: UNIT_TEST) { name type }
                targetSources(pathMode: NORMALIZED, filter: { target: { eq: \"App\" }, path: { contains: \"Shared\" } }) { target path }
                targetResources(filter: { target: { eq: \"App\" } }) { target path }
                targetBuildScripts(filter: { stage: PRE }) { target name stage inputPaths }
                dependencies(name: \"App\", filter: { type: FRAMEWORK }) { name type }
                dependents(name: \"Lib\", filter: { type: APP }) { name type }
                targetDependencies(filter: { type: FRAMEWORK }) { target name type }
                """
            )
        ]

        let fixture = try GraphQLBaselineFixture()
        for testCase in cases {
            try XCTContext.runActivity(named: testCase.name) { _ in
                let json = try fixture.evaluateToCanonicalJSON(query: testCase.query)
                try GraphQLSnapshot.assertSnapshot(data: json, named: testCase.name, subdirectory: "GraphQLBaseline")
            }
        }
    }

    func testAbsoluteAndBuildScriptSnapshotsMaskedRoot() throws {
        // Build fixture
        let fixture = try GraphQLBaselineFixture()
        // Determine project root for masking
        let mirror = Mirror(reflecting: fixture)
        guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
            XCTFail("Could not access projectQuery from fixture"); return
        }
        let m = Mirror(reflecting: qp)
        guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
            XCTFail("Failed to read projectPath"); return
        }
        let projectRoot = URL(fileURLWithPath: projectPath).deletingLastPathComponent().standardizedFileURL.path

        // Compose query with ABSOLUTE path modes + build script filter by name/target
        let query = """
        targetSources(pathMode: ABSOLUTE) { target path }
        targetResources(pathMode: ABSOLUTE) { target path }
        targetBuildScripts(filter: { name: { prefix: \"Post\" }, target: { eq: \"App\" } }) { target name stage }
        """
        var json = try fixture.evaluateToCanonicalJSON(query: query)
        // Mask project root to make snapshot stable across temp dirs (handle both raw and escaped slashes)
        let escapedRoot = projectRoot.replacingOccurrences(of: "/", with: "\\/")
        json = json
            .replacingOccurrences(of: projectRoot, with: "<ROOT>")
            .replacingOccurrences(of: escapedRoot, with: "<ROOT>")
            .replacingOccurrences(of: "\\/", with: "/")
        try GraphQLSnapshot.assertSnapshot(data: json, named: "absolute_and_buildscripts", subdirectory: "GraphQLBaseline")
    }
}
