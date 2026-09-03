# ADR-0002: Product and scheme name is SparkTread

- Status: Accepted
- Date: 2026-09-03
- Resolves: plan §24 open question 1 (working title), §18.3 scheme name

## Context

Planning documents use "Project Golden Eagle" and CI examples reference a `ProjectGoldenEagle` scheme; the repository is named SparkTread. Names get baked into the Xcode project, schemes, bundle identifiers, and CI, so this must be settled at M0.

## Decision

The project, Xcode scheme, SPM package, and repository name are **SparkTread**. "Project Golden Eagle" remains only as the historical codename inside existing planning documents; new documents and all code artifacts use SparkTread. CI commands from plan §18.3 substitute `-scheme SparkTread`.

## Consequences

- `Package.swift` package name, app target, and scheme: `SparkTread`.
- Bundle identifier root: `com.icell.sparktread` (adjustable before first release; changing it after TestFlight distribution requires a new app record).
- No mass rewrite of existing planning docs; the mapping is recorded here and in `DOCUMENT_INDEX.md`.
