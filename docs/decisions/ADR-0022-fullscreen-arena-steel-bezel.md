# ADR-0022: Fullscreen Arena with a White-Steel Bezel (GAME_RULES R5.9)

Status: Accepted (owner instruction of 2026-09-16: "画面还是全屏吧，不然感觉太浪费，只是可以把边缘 safe area 变成精钢")

## Context

R5 §15.1 (via the ADR-0018 consolidation) required the playable arena to
fit inside the system safe rectangle, so notched iPhones shrank the
playfield and left dark margins on both flanks. After playing the device
build the owner judged the margins wasted space and asked for a full-screen
picture, with the safe-area edge dressed as 精钢 (white steel).

## Decision

1. The arena scales to the FULL screen: cell points =
   min(surfaceW / 56, surfaceH / 27), centered on the whole surface.
   Safe-area insets no longer shrink or shift the playfield.
2. The gutter on the non-constraining axis is tiled with the white-steel
   wall texture (`px_white_steel_joint_15_15`, the PixelWallsWhite
   delivery) — a decorative bezel, not gameplay terrain.
3. System cutouts (notch, Dynamic Island, home indicator) may overlap the
   bezel — and, on extreme aspect ratios, the arena's outermost wall ring —
   but never the base, spawn points, or HUD-critical information.
4. Touch controls and the HUD keep their own safe-area padding (§15.2
   unchanged).

On current iPhones the height is the constraining axis, so the bezel forms
left/right bands exactly where the notch sits; on iPads the bands are
top/bottom.

## Consequences

- `ArenaLayout` loses its `SafeInsets` input and becomes a pure full-surface
  fit; the scene no longer re-layouts on inset changes and tiles the bezel
  during terrain build.
- GAME_RULES.md moves to R5.9 (§15.1 rewritten; Appendix B.6).
- Supersedes the safe-rectangle amendment recorded in ADR-0018 §3 and
  re-affirms plan D-016's original edge-to-edge intent, now with the
  decorated bezel.
- Purely presentational: no simulation state, checksum, or replay change.
