# ADR-0009: Universal Arena Dimensions Pinned at 56×27

Status: Accepted (owner decision; the one-shot M1 dimension tuning D-003 allows)  
Date: 2026-09-03  
Supersedes: the provisional 48×27 baseline (D-003, §6.1)

## Context

D-003 fixed one universal arena with a provisional 48×27 grid, tunable
exactly once through an ADR during M1 before combat content is authored.
With edge-to-edge rendering (ADR-0004) a 16:9 arena leaves ~79-point side
gutters on 19.5:9 iPhones. The owner reviewed the Movement Lab on the
iPhone 17 simulator and chose near-full-width ("56×27", 2026-09-03).

## Decision

1. The universal arena is **56×27 terrain cells** (X `0..55`, Y `0..26`;
   57,344×27,648 subunits). Aspect ratio 2.07:1. This is the final V1
   dimension; all stage content is authored against it.
2. Standard-tank display size on iPhones is unchanged (height-constrained
   uniform fit); side gutters shrink to roughly 20 points on 19.5:9 devices.
3. Consequences accepted with the choice: touch controls overlay the arena
   on most iPhones (the §17.4 reduced-opacity/auto-fade rules now apply
   broadly, and the M1 thumb-zone occlusion review gates them); iPads
   letterbox vertically with cells ≈ 21.3 points on the 11-inch class.
4. Movement lanes, subunits per cell, tank footprint, and every other
   spatial rule (ADR-0001) are unchanged.

## Alternatives considered

- Keep 48×27: rejected by owner — leaves wide unused gutters on phones.
- 52×27 middle ground: rejected by owner in favor of near-full-width.

## Gameplay consequences

Eight more columns of horizontal maneuvering space; stage authoring, AI
navigation budgets, and pacing targets use 56×27 from the start (no shipped
content existed at 48×27).

## Architecture consequences

`ArenaSpecification.universal` is 56×27. Fixtures and goldens regenerate;
the PixelProduction preview fixtures remain 48×27 art demos only.

## Migration cost

Zero shipped content; the M1 movement golden is intentionally regenerated
with this ADR as the review note.

## Tests affected

Arena constants, Movement Lab fixture geometry, and the M1 replay golden
(regenerated under this ADR).
