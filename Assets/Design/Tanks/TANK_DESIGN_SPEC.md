# Tank Design Specification

Status: Design lock candidate — pending art + gameplay review approval  
Visual direction: Soft Modern Mechanical Toy Arcade (D-019)  
Authority: `PRODUCT_IMPLEMENTATION_PLAN.md`, `ASSET_PRODUCTION_MANIFEST.md`  
Source form: parametric SVG masters, original geometry, no third-party or generated input

---

## 1. Canvas and technical master

| Property | Value |
|---|---|
| Master canvas | 256 × 256 px, transparent |
| World footprint | 2 × 2 terrain cells = 2048 × 2048 subunits (ADR-0001) |
| Authoring scale | 128 px per terrain cell |
| Canonical facing | UP; runtime rotates in 90° increments |
| Pivot | Exact canvas centre (128, 128) |
| Turret centre | (128, 134) — 6 px rear of pivot so the barrel reads forward |
| Widest chassis | 236 px (heavy), leaving 10 px effect padding per side |

## 2. Lighting rule (ADR-derived, F-20)

Rotating sprites carry **no directional key light**. Shading is a radial gradient centred on the
pivot only, which is invariant under 90° rotation. The upper-left key light applies exclusively to
non-rotating elements (terrain, base, UI). Contact shadow is a centred soft ellipse behind the tank.

## 3. Layer order (bottom → top)

```
contact shadow → tracks (animated) → hull → hull panel → armor overlay
→ equipment attachment → turret + barrel → power emissive bands
→ danger marker → ambient radial shading → damage overlay → identity ring (player only)
```

Each layer is a separate master file so runtime composition covers all 24 archetypes without
per-archetype paintings.

## 4. Chassis family

| Chassis | Total width | Hull | Track | Used for armor | Reads as |
|---|---:|---:|---:|---:|---|
| `scout` | 196 | 118 × 172 | 36 | 1 | Light, tapered nose, thin tracks |
| `standard` | 212 | 132 × 188 | 42 | 2 | Baseline proportions |
| `armored` | 224 | 142 × 198 | 46 | 3–4 | Front shoulder plates, thicker tracks |
| `heavy` | 236 | 150 × 206 | 52 | 5–6 | Double front plate, side skirts, widest tracks |

## 5. Turret silhouettes — weapon identity without colour

Each family is identifiable in pure grayscale at 28 pt:

| Family | Silhouette signature |
|---|---|
| `normal` | One medium barrel, square muzzle collar |
| `rapid` | Twin thin barrels + rear ammo drum |
| `fire` | Short thick barrel with flared conical nozzle + fuel canister |
| `ap` | Longest, thinnest barrel, twin muzzle-brake collars, base bracing ring |
| `explosion` | Short fat mortar bore with wide muzzle ring and visible bore eye |
| `mine` | **No forward barrel** — top hopper + rear dispenser chute with visible mine disc |

`mine` is deliberately the only barrel-less family; it is the fastest read on the battlefield.

## 6. Progression overlays

- **Armor tier 0–3** (from armor 1 / 2 / 3–4 / 5–6): side plates → front bolted plate → full skirt + rails.
- **Power level 0–3**: 0–3 emissive bands on the barrel in the family signal colour.
- **Damage light / heavy / critical**: scorch → scorch + crack → crack + blown panel + hot core.
- **Danger marker**: chevron above the hull, applied where `power_level >= 3` (`rapid_d`, `fire_d`, `explosion_d`).

## 7. Equipment attachments

| Equipment | Attachment |
|---|---|
| `amphi_tank` | Pontoon capsules outboard of both tracks, signal-tinted core |
| `anti_skid` | Six cleat studs per track edge |
| `shield_of_moon` | Crescent projector arc across the hull nose |
| `memory_of_sea` | Four-segment chromatic ring on the hull rear |

## 8. Palette

Player is blue-cyan; each enemy weapon family owns one hue, per manifest §2.4. Shape carries
meaning in addition to colour — no archetype is distinguished by colour alone.

| Role | Hull | Panel | Signal |
|---|---|---|---|
| Player | `#3F6CB0` | `#5C8FCE` | `#5FC6D8` |
| Normal | `#D8A64E` | `#E6BE7C` | `#F5A83A` |
| Rapid | `#9DB47C` | `#B6C99A` | `#C9E24A` |
| Fire | `#E09070` | `#EDAE90` | `#F7BC44` |
| AP | `#9C8CC4` | `#B3A5D5` | `#E574C4` |
| Explosion | `#C97558` | `#DB9375` | `#F2B24E` |
| Mine | `#C7A265` | `#D7B98B` | `#5FC6D8` |

Tracks are rubberised warm charcoal per family. Exact accessible values lock only after grayscale
and colour-vision-deficiency tests (manifest §2.4).

## 9. Archetype composition

All 24 enemy archetypes are produced by module selection, never by unique paintings. The mapping
from the recovered attribute table to chassis, overlays, and attachments is in `archetype_map.csv`
and is the authority for content encoding (GE-023).

## 10. Outstanding review gates

Before this becomes a shipping lock:

- [ ] Grayscale and colour-vision-deficiency comparison sheets pass;
- [ ] 28 pt readability confirmed on the physical floor device (ADR-0004);
- [ ] Art reviewer and gameplay reviewer sign-off (manifest §8);
- [ ] Raster export pipeline (SVG → PNG atlas) and pivot calibration verified;
- [ ] Tread animation cadence validated in motion at final speed levels.
