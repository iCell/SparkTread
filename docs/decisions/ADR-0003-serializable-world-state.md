# ADR-0003: Serializable World State and Resimulation Obligations

Status: Accepted  
Date: 2026-09-01  
Related findings: F-04, F-05 (partial), F-23

## Context

Every plausible future co-op mechanism (late join, reconnect, host migration, rollback, desync recovery) requires serializing, restoring, and cheaply copying complete simulation state, and rollback requires resimulating many ticks per frame. Plan v2.1 required only presentation snapshots and between-stage saves; unserializable or reference-entangled internal state would have been discovered only when networking work started — the one identified defect class that forces a later rewrite. iOS lifecycle behavior (termination of a suspended app mid-stage) requires the same capability.

## Decision

V1 obligations under D-018 now include:

1. `WorldState` is a **value type** and **fully `Codable`**, including RNG stream positions, turn-buffer/assist state, slide state, and deferred effects. Authoritative state never lives in class graphs.
2. From M1 onward, a required test: run N ticks → serialize → restore → run M ticks → checksums equal an uninterrupted N+M run.
3. `suspended_session.json` stores a mid-stage snapshot plus the command log when the app leaves the foreground mid-stage; validated on load, deleted on stage completion/abandonment.
4. Performance target: headless resimulation at ≥10× real time on the minimum supported device.
5. Periodic state checksums are **required** in development, test, and golden-replay configurations; optional in release.

No networking code ships in V1.

## Alternatives considered

- Defer everything to the pre-network ADR: rejected — unserializable state discovered then is a rewrite, not a policy choice.
- Memory-only pause: rejected — iOS termination of suspended apps loses mid-stage progress.

## Gameplay consequences

Mid-stage resume after interruptions or termination; no player-visible rule changes.

## Architecture consequences

Constrains internal representation to COW value semantics; forbids hidden clock/reference state in the core.

## Migration cost

Zero now; retrofitting later was the risk this ADR removes.

## Tests affected

New serialize/restore/resume integration test; lifecycle scene tests; resimulation throughput measurement in the stress fixture.
