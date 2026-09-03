# ADR-0001: Spatial Unit System

Status: Accepted  
Date: 2026-09-01  
Related findings: F-01

## Context

Plan v2.1 defined three mutually incompatible spatial systems: `1024` subunits per terrain cell (§6.1), `256 subpixels = 1 logical pixel` with an undefined "logical pixel" (§7.1), and reference-game pixel language ("16×16 cell", "8×8 quadrant") leaked into normative text (§7.3/§7.4). The weapon schema was denominated in `subpx` with no conversion defined. Independent agents implementing movement, terrain, and weapon data would have chosen different quantizations.

## Decision

There is exactly one authoritative spatial unit: the **subunit**.

- 1 terrain cell = `1024 × 1024` subunits.
- 1 destruction quadrant = `512 × 512` subunits (four per cell).
- Standard tank footprint = `2048 × 2048` subunits minus a PROVISIONAL collision inset.
- All schema fields for speed, acceleration, radius, and distance are expressed in subunits (`*_subunits_*`); "subpixel" and "logical pixel" are removed from the vocabulary.
- Reference conversion: 1 reference-game pixel (16-pixel-cell era) = `64` subunits. Reference constants MUST pass through this documented conversion; pixel values never appear in modern content data.

## Alternatives considered

- Keep the 256-subpixel/logical-pixel system: rejected — "logical pixel" was undefined and produced awkward non-power-of-cell math.
- Adopt the reference 16-pixel grid directly: rejected — couples modern authoritative data to a research artifact and to a specific art scale.

## Gameplay consequences

None at runtime. Reference-derived tuning values are converted once through the documented factor.

## Architecture consequences

Weapon/terrain schema fields renamed before any content is encoded. Content-validator ranges are expressed in subunits, including the per-tick displacement sanity cap (`1023` subunits).

## Migration cost

Zero: applied before implementation begins.

## Tests affected

All movement, collision, and weapon fixtures use subunits; the conversion factor is itself covered by a unit test against known reference values.
