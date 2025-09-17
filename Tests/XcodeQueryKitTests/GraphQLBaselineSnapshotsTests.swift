import XCTest

final class GraphQLBaselineSnapshotsTests: XCTestCase {
    struct SnapshotCase {
        let name: String
        let query: String
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
}
