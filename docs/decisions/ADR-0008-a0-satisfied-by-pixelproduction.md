# ADR-0008: A0 Style-Lock Satisfied by the PixelProduction Delivery

Status: Accepted (owner decision)  
Date: 2026-09-03  
Related: ADR-0006, plan §19 A0

## Context

A0 required style-lock masters (player tank, enemy, terrain sample,
minimum-iPhone readability board) so the M1 legibility gate could run with
representative silhouettes. The PixelProduction delivery provides a complete
shipped art direction (17 atlases, 1,617 entries) already rendered through
the real SpriteKit pipeline and reviewed by the owner in the simulator
(ADR-0006).

## Decision

1. A0 is satisfied by the PixelProduction delivery; no separate Phase 0
   controlled-redraw masters are produced ("A0 就算已满足", owner,
   2026-09-03).
2. The delivery's provenance record is its own documentation
   (`docs/pixel/`, generation prompts retained in the source delivery).
3. M1 proceeds immediately; the arena-dimension decision may use the pixel
   art as its representative silhouettes.

## Alternatives considered

- Running the original Phase 0 redraw workflow anyway: rejected — duplicate
  effort against an already accepted art direction.

## Gameplay consequences

None.

## Architecture consequences

None.

## Migration cost

Zero.

## Tests affected

The M1 legibility gate uses PixelProduction sprites (per ADR-0006).
