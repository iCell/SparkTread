# ADR-0002: Command Contract and Input-Buffer Ownership

Status: Accepted  
Date: 2026-09-01  
Related findings: F-02, F-03

## Context

The plan used two names (`PlayerCommand`, `TankCommand`) for the external command boundary; tick-order step 4 validated "activation, continue, and respawn requests" no command field could express; the command type's `actor: player | ai` variant implied AI commands enter the external ingestion path; and ownership of turn buffering / alignment assistance (adapter vs. core) was undefined. This is the exact boundary the future two-player online co-op depends on.

## Decision

1. **`PlayerCommand` is the only external input contract**: `player_id`, `target_tick`, `move_direction`, `normal_fire_pressed`, `special_fire_pressed`, and a versioned `session_request` enum (`none | confirm | continue | activation`).
2. **AI intents are internal-only.** `EnemyBrain` emits a `TankIntent` with the same movement/fire fields, derived deterministically inside the simulation. AI intents are never transmitted, recorded as external input, or accepted by the ingestion API.
3. **Missing command = neutral input.** A tick with no command for a player resolves to no movement, no fire, no request (this is also the sparse-replay and delay-based-netcode semantics).
4. **Adapters resolve physical input; the core owns buffering.** Input adapters resolve concurrent presses to at most one held direction per tick and never inspect collision state. `GameCore` owns turn buffering and alignment assistance (both depend on authoritative collision legality); their state lives in `TankState`, is included in snapshots, checksums, and serialization, and their windows are ruleset data.

## Alternatives considered

- Adapter-side buffering: rejected — requires collision knowledge in the adapter and makes replays capture post-buffer commands resolved against stale state.
- Overloading `confirm_pressed` for session requests: rejected — unversionable and ambiguous.
- Keeping AI in the external command union: rejected — invites treating AI commands as ingestible input, which breaks lockstep networking.

## Gameplay consequences

Buffered turns behave identically across touch, keyboard, controller, replay, and future remote input.

## Architecture consequences

A future network adapter deserializes authenticated remote `PlayerCommand` values only; it never calls tank methods or mutates `WorldState`. Buffer state slightly enlarges the checksum surface.

## Migration cost

Zero: applied before implementation begins.

## Tests affected

Buffered-turn replay tests; the two-`PlayerID` command-stream core fixture; command-validation unit tests.
