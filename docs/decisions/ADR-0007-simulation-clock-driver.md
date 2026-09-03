# ADR-0007: Simulation Clock Driver Is a Display-Link Accumulator Owned by the Application Adapter

Status: Accepted  
Date: 2026-09-03  
Related: plan §17.5, D-017, D-018

## Context

The fixed 60 Hz deterministic simulation needs exactly one clock authority.
SpriteKit offers `SKScene.update(_:)` and automatic view pausing; relying on
them would tie simulation progress to scene presentation, making pausing,
backgrounding, 120 Hz ProMotion, Low Power Mode, and headless replay each a
potential second clock. The plan requires this pinned by an M0/M1 decision
record (§17.5).

## Decision

1. The authoritative clock driver is a display-link-driven fixed-timestep
   accumulator (`CADisplayLink` on iOS/iPadOS, the equivalent display-link
   mechanism on macOS) owned by the application adapter layer — not by
   `GameCore`, not by any `SKScene`.
2. Each display-link callback adds elapsed wall time to an accumulator and
   steps the simulation zero or more whole ticks of exactly 1/60 s.
   Remainder time carries over; ticks are never fractional and never scaled
   by refresh rate, Low Power Mode, or thermal state.
3. The accumulator clamps a maximum of 6 ticks per callback; longer gaps
   (suspension, debugger pauses) MUST route through the explicit
   pause/resume flow rather than a tick burst.
4. `SKScene.update(_:)`, SpriteKit actions, and SpriteKit's automatic view
   pausing MUST NOT advance, pause, or otherwise gate the simulation.
   Presentation reads snapshots/events; pausing gameplay is an explicit
   application-layer state change (§17.5), never a side effect of view state.
5. Headless execution (tests, replays, resimulation) drives the same
   tick-stepping API directly with no display link, which is why the driver
   lives in the adapter and the stepping API lives at the application/core
   boundary.

## Alternatives considered

- `SKScene.update` as the driver: rejected — couples simulation to scene
  presentation and to SpriteKit's automatic pausing (the exact hazard §17.5
  forbids).
- A GCD/Timer loop: rejected — drifts against display refresh, wakes the CPU
  off-cadence, and still needs an accumulator anyway.
- Variable timestep with interpolation: rejected — violates the fixed-tick
  determinism foundation (D-018).

## Gameplay consequences

None to rules. Frame-rate changes affect rendering smoothness only.

## Architecture consequences

The application adapter owns the driver; `GameCore` exposes only a pure
step-by-ticks entry point. Scene code never calls the stepper.

## Migration cost

Zero: pinned before the M1 kernel is written.

## Tests affected

M1 kernel tests drive ticks directly; a scene-integration test must assert
that pausing the `SKView` does not advance or halt simulation ticks except
through the explicit pause flow.
