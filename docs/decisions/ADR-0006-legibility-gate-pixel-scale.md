# ADR-0006: Legibility Gate Revised to Accept the PixelProduction Tank Scale

Status: Accepted (owner decision; physical-device confirmation still required at the M1 gate)  
Date: 2026-09-03  
Supersedes in part: the 28×28-point tank-footprint value in ADR-0004 and §17.3

## Context

The PixelProduction art delivery renders the full 48×27 arena with a standard
tank whose visible bounding box measures approximately 19–20×15 screen points
on the 390×844-point floor-device class — below the 28×28-point provisional
gate pinned by ADR-0004. The delivery's own coverage document flagged this
conflict as unresolved rather than silently waiving it.

On 2026-09-03 the owner reviewed the delivery running in the real SpriteKit
pipeline on the iPhone 17 simulator (battle arena, roster, directions, and
item-sheet fixtures) and judged the current tank size appropriate ("按照现在的
效果图我觉得大小挺合适").

## Decision

1. The 28×28-point minimum tank footprint is replaced. The accepted baseline
   is the PixelProduction delivery's current scale: a standard tank visible
   bounding box of approximately 19–20×15 points on the floor device, with
   18 points minimum visible width as the new hard floor.
2. All other ADR-0004 gates stand unchanged: 44×44-point touch targets,
   silhouette identifiability without color, no opaque HUD over critical
   entities, the five-second screenshot review, and the thumb-zone occlusion
   review.
3. The M1 gate venue is unchanged: final confirmation happens on a physical
   floor-class iPhone at normal viewing distance. This ADR records owner
   acceptance from simulator review on a desktop display; if the physical
   review fails, the sanctioned fixes remain those of ADR-0004 §4 (fewer
   cells, larger unit-to-cell ratio, reduced density, UI revision — never
   cropping, scrolling, or stretching).

## Alternatives considered

- Enlarging the pixel art to meet 28×28: rejected by owner review — the
  current scale reads well and preserves full-arena density.
- Reducing arena cells to enlarge tanks: rejected for the same reason;
  48×27 remains the baseline.
- Leaving the conflict unresolved: rejected — the plan requires gate changes
  to go through an ADR, not a silent waiver.

## Gameplay consequences

None to rules. Arena logic, unit footprints in subunits, and collision are
unaffected (ADR-0001).

## Architecture consequences

None. Presentation scale remains a renderer concern; the showcase's 0.82
tank scale factor stays a test value until M1 pins the final presentation
scale alongside the pixel-alignment strategy.

## Migration cost

Zero. This narrows future rework risk by locking the art scale direction
before M1 arena-dimension finalization.

## Tests affected

The M1 legibility gate procedure tests against the revised 18-point minimum
width; device-aspect scene fixtures are unchanged.
