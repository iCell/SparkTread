# ADR-0004: Arena Rendering Policy and Minimum-Device Floor

Status: Accepted; the 28×28-point tank-footprint gate value is superseded in part by ADR-0006  
Date: 2026-09-01  
Related findings: F-06, F-08 (context), F-19 (layout consequence)

## Context

The M1 legibility gate (28×28-point standard tank at 48×27 cells) is arithmetically decidable today: 375-point-height iPhones (SE, mini) yield a 27.8-point tank and fail outright; 390-point devices pass (28.9 pt) only if the arena uses the full screen height, bleeding beneath the home indicator. The plan neither pinned the candidate minimum device nor stated whether the arena may render under safe-area insets — yet the M1 dimension ADR is one-shot.

## Decision

1. **Edge-to-edge arena**: the gameplay arena renders edge-to-edge and MAY extend beneath system UI overlays (rounded corners, sensor housing, home indicator). HUD and interactive controls remain safe-area-aware. Bottom-edge system gestures are deferred during gameplay.
2. **Device floor**: the pinned minimum-supported-device floor is the 390×844-point class (iPhone 12/13/14-generation standard sizes and later). 375-point-height devices are below the floor. The floor may widen (support older devices) only through a new ADR after the M1 gate passes with margin; it never shrinks silently.
3. **Gate venue**: the M1 legibility gate runs on a physical floor-class device using the A0 style-lock masters, not debug rectangles.
4. **Sanctioned fixes** if the gate fails remain those already permitted by D-003: fewer cells (~16:9 preserved), larger tank-to-cell ratio, reduced visual density, or UI revision. Scrolling, cropping, stretching, and device-dependent playable area remain prohibited.
5. **Touch layout consequence**: default touch controls anchor in the horizontal gutters produced by uniform arena fit on taller-than-16:9 devices, overlaying the arena only on ~16:9 devices; a thumb-zone occlusion review is part of the gate.

## Alternatives considered

- Supporting 375-point devices: rejected — fails the 28-point gate at 48×27; keeping them forces a coarser grid and loses the reference-heritage battlefield density.
- Respecting the bottom safe inset for the arena: rejected — drops the tank below 28 points on every current iPhone.
- Lowering the 28-point gate: rejected — the gate encodes the readability pillar (PILLAR-03/-04), not a tunable preference.

## Gameplay consequences

None to rules; the whole arena and all tanks remain visible on every supported device.

## Architecture consequences

Viewport layout, gesture deferral, and gutter layout live in the presentation/input adapters; `GameCore` is unaffected.

## Migration cost

Zero now. Widening the floor later is additive.

## Tests affected

Device-aspect scene fixtures; the M1 legibility gate procedure; touch-layout occlusion review.
