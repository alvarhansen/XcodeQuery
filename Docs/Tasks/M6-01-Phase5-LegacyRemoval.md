# M6-01 Phase 5 — Legacy Parser Decommission

Goal
- Remove the bespoke GraphQL parser/AST/executor once GraphQLSwift has proven stable in production.

Context
- With the CLI flipped and sufficient bake time elapsed, keeping two execution paths adds maintenance burden and confuses future contributors.

Tasks
- Delete legacy parser, AST types, and associated utilities from `Sources/XcodeQueryKit/GraphQL.swift`.
- Excise feature flags or fallback pathways introduced in Phase 4.
- Clean up tests/fixtures that only targeted the legacy implementation, replacing them with GraphQLSwift-focused coverage where needed.
- Update documentation to reflect the single-source implementation, including contribution guidelines and architecture diagrams.
- Prepare release notes summarizing the removal and highlighting any follow-up migration advice for plugin authors.

Deliverables
- Codebase free of legacy parser artifacts with green `swift build`/`swift test`.
- Simplified documentation and onboarding materials pointing exclusively to GraphQLSwift implementation details.
- Release note entry prepared for the next tag.

Dependencies
- Requires confidence from production usage post-Phase 4, including stability metrics and absence of critical regressions.

Risks & Mitigations
- Risk: Hidden tooling still depends on legacy internals. Mitigation: audit internal consumers before deletion and offer migration guidance.
- Risk: Regression discovered post-removal. Mitigation: keep git tag/branch to restore legacy code quickly if needed.
