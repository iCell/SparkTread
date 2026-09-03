# ADR-0001: Adopt PixelProduction pixel art as the product art direction

- Status: Accepted
- Date: 2026-09-03
- Supersedes: plan §4 D-019 (soft modern mechanical toy style), D-020 (v2 soft styleboards), plan §12.6

## Context

The plan fixed a "Soft Modern Mechanical Toy Arcade" direction referencing `styleboards/*_v2_soft.png`. Since then, a complete pixel-art asset delivery was produced under `PixelProduction/` (17 atlases, 1,617 sprites, verified manifest, SpriteKit runtime adapters) in a "refined pixel 2.5D" style with an elevated near-overhead viewpoint. The styleboards were deliberately deleted in commit `5a3d6e1`.

## Decision

The product art direction is the pixel style delivered in `PixelProduction/`. The soft-toy styleboards are retired and will not be restored. All references to `styleboards/` in planning documents are void; `PixelProduction/` (manifest + docs) is the art authority.

The gameplay camera remains a fixed full-map view; the pixel art's slight downward side extrusion is a sprite-level treatment and does not change the top-down arena logic, coordinate system, or collision model (plan §6.1 unchanged).

## Consequences

- Asset work sources exclusively from `PixelProduction/Atlases` + `Metadata/pixel_assets.json` via the `PixelArt`/`PixelPresentation` runtime adapters.
- The plan's asset-generation pause stays in effect: gaps (campaign thumbnails, audio, branding) are filled only on explicit request.
- The provisional 28×28 pt tank legibility gate was calibrated for the soft-toy style; ADR-0003 revises it for this art.
- `ASSET_REQUIREMENTS_LIST_ZH.md` §40's styleboard checkboxes are historical record, not current references.
