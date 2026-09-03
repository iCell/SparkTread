# ADR-0003: Keep the 48×27 arena; revise the tank legibility gate

- Status: Accepted (provisional until M1 real-device review)
- Date: 2026-09-03
- Revises: plan §17.3 M1 provisional gate "tank visible footprint ≥ 28×28 pt"

## Context

With the full 48×27 arena always visible (PILLAR-03, fixed), the delivered pixel tanks measure ~19.4×14.9 pt on a 667×375 iPhone and ~20.3×15.5 pt on 844×390 — below the provisional 28×28 pt gate. The plan's permitted remedies include shrinking the grid, but reducing 48×27 to a grid that yields 28 pt tanks (~36×20) cuts tactical area by roughly 40% and weakens the design pillar the gate exists to serve: complete battlefield awareness. Bigger tanks mean a smaller battlefield; the battlefield is the product.

The 28×28 pt figure was calibrated for the retired soft-toy style (ADR-0001). The PixelProduction art was QA'd at the smaller size and ships dedicated readability aids: player/enemy badges, status rings, high-contrast silhouettes, direction-distinct turrets, and warning telegraphs.

## Decision

1. The arena stays **48×27 cells** with tanks at 2×2 cells. The one-time M1 arena-size ADR window is hereby used.
2. The hard footprint gate is replaced by a functional gate on the minimum supported iPhone, judged with the whole arena visible:
   - player tank, base, highest-threat enemy, and active special-weapon effect identifiable in a five-second screenshot review;
   - projectiles, mines, pickups, and telegraphs distinguishable without relying on color alone;
   - player/enemy affiliation readable at a glance (badges/status rings count as legitimate aids);
   - touch targets remain ≥ 44×44 pt regardless of art size.
3. Minimum supported iPhone for this gate is the 844×390 pt class (iPhone 12/13/14 non-mini and later). Smaller legacy devices may run the game but are not gate devices.
4. Mandatory M1 verification on a physical device. If the functional gate fails there, the fallback order is: raise the sprite scale / unit-to-cell ratio, simplify visual density, then — last resort, new ADR — reduce the grid. Cropping, scrolling, and non-uniform stretching remain forbidden.

## Consequences

- M1 exit criteria and §18.3's device gate test against this ADR's criteria, not the 28×28 pt number.
- The PixelProduction QA doc's flagged conflict (`COVERAGE_AND_QA_ZH.md`) is resolved by this ADR pending the M1 device check.
- The `0.82` sprite scale used in QA fixtures stays a starting point, not a locked constant.
