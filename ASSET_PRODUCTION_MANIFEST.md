# Project Golden Eagle

## Visual and Audio Asset Production Manifest

Document version: 0.2  
Status: Production baseline; soft v2 visual direction approved; bulk asset generation paused pending an explicit later request  
Visual direction: Soft Modern Mechanical Toy Arcade  
Primary presentation: 2D orthographic top-down, full arena always visible  
Primary device: iPhone landscape  

---

## 1. Purpose

This document lists the complete asset families required for the first public-quality campaign and defines how each family is created, reviewed, exported, and licensed. It is an implementation companion to `PRODUCT_IMPLEMENTATION_PLAN.md`.

The current documentation task is enumeration-only. No asset listed here is authorized for generation merely by appearing in this document.

The inventory distinguishes:

- **Generated source**: image generation can create an original starting image or concept.
- **Artist finish**: a human or controlled editing pass must normalize silhouette, palette, topology, alignment, and animation consistency.
- **Code-generated**: SpriteKit particles, shaders, masks, geometry, or runtime composition are preferable to a bitmap sequence.
- **Engine-rendered**: thumbnails or composites should be captured from the actual game instead of painted independently.
- **Audio production**: original synthesis, recording, composition, or commissioned work; image generation does not produce these deliverables.

No generated image becomes shipping art merely because it looks attractive. Every shipping asset must pass gameplay readability, technical, provenance, and consistency review.

---

## 2. Fixed Visual Language

### 2.1 View and projection

- Strict orthographic top-down view.
- No isometric perspective, horizon, three-quarter camera, lens distortion, or foreshortened battlefield geometry.
- Tanks may use shallow modeled highlights and short contact shadows, but their footprints and facing remain unambiguous.
- Every gameplay asset must remain readable while the entire arena is visible on the minimum supported iPhone.

### 2.2 Shape language

- Compact mechanical-toy proportions with moderately rounded silhouettes.
- Broad tracks, clear turret silhouette, large readable weapon barrel.
- Rounded armor corners, large simple color panels, and restrained industrial seams.
- Friendly and tactile without faces, eyes, plush-toy cues, or preschool styling.
- Avoid realistic military insignia, national markings, copied vehicle designs, and direct imitation of the reference game's sprites.
- Player silhouette: agile, heroic, blue-cyan energy accents.
- Enemy silhouettes: warmer warning accents and weapon-family-specific turret profiles.
- Dangerous variants differ by shape and animation, never by color alone.

### 2.3 Materials

- Satin enamel-painted metal with small soft molded-plastic accents.
- Rubberized tracks.
- Small emissive energy strips for state readability.
- Rivets, scratches, grime, hard bevels, and tiny surface parts are used sparingly.
- Terrain resembles a premium tabletop mechanical playset: tactile, clean, durable, and slightly exaggerated.
- Damage uses scorch, cracks, sparks, and detached toy-like panels without gore.

### 2.4 Palette

Provisional master palette:

| Role | Primary | Secondary | Signal |
|---|---|---|---|
| Player | soft navy/clear blue | warm light gray | cyan-white |
| Normal enemy | amber | warm cream | orange-white |
| Rapid enemy | sage green | warm gray | electric lime |
| Fire enemy | cream/coral | warm charcoal | orange-yellow |
| AP enemy | muted violet | soft gray | magenta-white |
| Explosion enemy | muted coral | warm charcoal | amber-white |
| Mine enemy | tan/bronze | warm charcoal | amber/cyan rings |
| Friendly/base | ivory | blue | cyan-gold |
| Danger | muted red/coral | warm charcoal | orange-white |

Exact accessible color values will be locked only after grayscale and color-vision-deficiency tests.

### 2.5 Lighting

- Consistent soft key light from the upper-left.
- Short, soft contact shadow directly below each object.
- No long shadow may hide grid position or overlap another tank.
- Emissive weapon effects may temporarily override local color but not silhouette.

---

## 3. Technical Master Specifications

### 3.1 World-to-art scale

- Universal arena baseline: 48×27 base cells, provisional until the M1 legibility gate.
- Standard tank footprint: 2×2 base cells.
- Authoring master for one base terrain cell: 128×128 px.
- Authoring master for one standard tank: 256×256 px transparent canvas.
- Runtime world sizes are independent of source pixels.
- Source masters should retain layers where the production tool supports them.

### 3.2 Export

- Raster gameplay assets: lossless PNG with alpha, sRGB.
- Opaque environment textures: lossless PNG unless measured package size requires a reviewed alternative.
- Vector UI source: SVG/PDF or custom SF Symbol source where appropriate; rasterize through the Apple asset pipeline when required.
- SpriteKit atlases group assets by load lifetime, not merely by visual category.
- Transparent padding and pivot metadata must be standardized per asset family.
- Texture names use stable lowercase snake case IDs.

### 3.3 Runtime rotation and animation

- Strict top-down tanks use one canonical UP-facing master and rotate in 90-degree increments at runtime unless art review proves direction-specific frames necessary.
- Chassis, turret, equipment, damage, team-color, and shadow should be separate compositing layers where practical.
- Movement tread loops use two or four frames.
- Destruction, fire, smoke, shield, spawn, and pickup glows should prefer code-driven particles and small reusable texture primitives.

---

## 4. Complete Asset Inventory

Quantities below are source-art units, not final atlas-frame counts. Variants composed from masks, palettes, particles, or runtime rotation do not require duplicated paintings.

### A. Visual development and style control

| ID | Asset | Qty | Method | V1 priority |
|---|---|---:|---|---|
| ART-DIR-001 | Full-arena gameplay style board | 1 | Generated source + art review | P0 |
| ART-DIR-002 | Player/enemy tank family sheet | 1 | Generated source + art review | P0 |
| ART-DIR-003 | Terrain/material/effect language sheet | 1 | Generated source + art review | P0 |
| ART-DIR-004 | HUD/touch-control style board | 1 | Generated source + UX review | P0 |
| ART-DIR-005 | Master palette and grayscale sheet | 1 | Artist finish | P0 |
| ART-DIR-006 | Shape and silhouette comparison sheet | 1 | Artist finish | P0 |
| ART-DIR-007 | Lighting/contact-shadow reference | 1 | Artist finish | P0 |

### B. Player tank

| ID family | Asset | Source units | Method |
|---|---|---:|---|
| TANK-PLAYER-CHASSIS | Main player chassis | 1 | Generated source + artist finish |
| TANK-PLAYER-TRACKS | Left/right tread animation | 4 frames | Artist finish |
| TANK-PLAYER-TURRET-NORMAL | Normal cannon turret | 1 | Generated source + artist finish |
| TANK-PLAYER-TURRET-RAPID | Rapid cannon turret | 1 | Generated source + artist finish |
| TANK-PLAYER-TURRET-FIRE | Fire projector turret | 1 | Generated source + artist finish |
| TANK-PLAYER-TURRET-AP | Armor-piercing turret | 1 | Generated source + artist finish |
| TANK-PLAYER-TURRET-EXPLOSION | Explosion cannon turret | 1 | Generated source + artist finish |
| TANK-PLAYER-TURRET-MINE | Mine-layer mechanism | 1 | Generated source + artist finish |
| TANK-PLAYER-ARMOR | Armor tier overlays | 4 | Artist finish |
| TANK-PLAYER-POWER | Power tier barrel/emissive overlays | 4 | Artist finish |
| TANK-PLAYER-DAMAGE | Light/heavy/critical damage overlays | 3 | Artist finish |
| TANK-PLAYER-SPAWN | Spawn hologram primitives | 3 | Generated source + code animation |
| TANK-PLAYER-SHADOW | Common contact shadow | 1 | Artist finish |
| TANK-PLAYER-SELECTION | Player identity ring/marker | 2 states | Code-generated + texture primitive |

### C. Enemy tank system

The 24 enemy archetype slots are assembled from reusable modules instead of 24 unrelated paintings.

| ID family | Asset | Source units | Method |
|---|---|---:|---|
| TANK-ENEMY-CHASSIS | Scout, standard, armored, heavy chassis | 4 | Generated source + artist finish |
| TANK-ENEMY-TURRET | Normal, Rapid, Fire, AP, Explosion, Mine turrets | 6 | Generated source + artist finish |
| TANK-ENEMY-ARMOR | Armor reinforcement overlays | 4 | Artist finish |
| TANK-ENEMY-POWER | Weapon-power indicators | 4 | Artist finish |
| TANK-ENEMY-EQUIPMENT | Amphi, AntiSkid, Moon Shield, Memory of Sea attachments | 4 | Generated source + artist finish |
| TANK-ENEMY-DANGER | Elite/danger silhouette attachments | 3 | Artist finish |
| TANK-ENEMY-DAMAGE | Light/heavy/critical damage overlays | 3 | Artist finish |
| TANK-ENEMY-SPAWN | Enemy spawn telegraph primitives | 3 | Generated source + code animation |
| TANK-ENEMY-SHADOW | Common contact shadows by chassis size | 4 | Artist finish |
| TANK-ENEMY-COLOR | Accessible palette masks for six weapon families | 6 | Artist finish + shader/runtime tint |

Required archetype coverage:

```text
normal_a normal_b normal_c normal_d
rapid_a rapid_b rapid_c rapid_d
fire_a fire_b fire_c fire_d
ap_a ap_b ap_c ap_d
explosion_a explosion_b explosion_c explosion_d
mine_a mine_b mine_c mine_d
```

### D. Projectiles, weapons, and combat VFX

| ID family | Assets | Method |
|---|---|---|
| WPN-NORMAL | Projectile, muzzle flash, trail, terrain impact, armor impact | Generated primitives + particles |
| WPN-RAPID | Projectile, muzzle flash, streak, ricochet/impact | Generated primitives + particles |
| WPN-FIRE | Fire bolt, flame core, burning patch, smoke, extinguish | Generated primitives + particles/shader |
| WPN-AP | AP projectile, piercing line, entry spark, exit spark | Generated primitives + particles |
| WPN-EXPLOSION | Shell, warning pulse, blast core, blast ring, debris | Generated primitives + particles |
| WPN-MINE | Mine body levels 0–3, ownership mark, arming ring, trigger ring, blast | Generated source + artist finish + particles |
| COMBAT-HIT | Armor flash, shield hit, invulnerable deflect, dry fire | Particles + small textures |
| COMBAT-DEATH | Tank explosion, smoke, fragments, scorch decal | Particles + reusable fragments |
| COMBAT-STATUS | Freeze, slow, airborne/launch, invincibility, stun | Generated primitives + shader/particles |

Minimum independent bitmap primitives:

- 6 projectile cores;
- 6 muzzle-flash shapes;
- 6 impact shapes;
- 4 mine bodies;
- 3 smoke puffs;
- 6 debris fragments;
- 5 status-effect masks/rings;
- 4 scorch/crack decals.

### E. Auxiliary equipment

| ID | Asset | States | Method |
|---|---|---:|---|
| EQ-AMPHI | AmphiTank flotation/propulsion attachment | idle + water wake | Generated source + artist finish |
| EQ-ANTISKID | AntiSkid track cleats | idle + active glint | Generated source + artist finish |
| EQ-MOON-SHIELD | Crescent shield projector | idle + active field | Generated source + particles |
| EQ-MEMORY-SEA | Chromatic ring/sea-memory module | idle + active aura | Generated source + shader |

Each equipment requires:

- tank attachment sprite;
- pickup/HUD icon;
- activation effect;
- compact status silhouette;
- grayscale-readable identifier.

### F. Pickups and treasure icons

All icons require normal, newly-spawned glow, available-to-collect, and collected-flash presentation; glow/flash are shared code effects.

| ID | Internal name | Required icon concept |
|---:|---|---|
| 00 | speed_up | track/turbine upgrade |
| 01 | armor_up | armor plate |
| 02 | power_up | energized cannon |
| 03 | level_up | combined three-axis upgrade |
| 04 | max_speed_power | dual maximum gauge |
| 05 | amphi_tank | flotation module |
| 06 | anti_skid | track cleat module |
| 07 | shield_of_moon | crescent shield |
| 08 | memory_of_sea | chromatic sea-memory ring |
| 09 | score_200 | small score token |
| 10 | score_500 | medium score token |
| 11 | score_1000 | large score token |
| 12 | score_2000 | maximum score token |
| 13 | invincibility | armored star/core field |
| 14 | base_shield | protected base emblem |
| 15 | freeze_enemy | frozen enemy silhouette |
| 16 | bomb | battlefield pulse bomb |
| 17 | extra_life | reserve tank/life core |
| 18 | max_armor_ammo | reinforced armor crate |
| 19 | ammo_crate | ammunition module crate |
| 20 | rapid_weapon | rapid turret chip |
| 21 | fire_weapon | fire turret chip |
| 22 | ap_weapon | piercing turret chip |
| 23 | explosion_weapon | explosion turret chip |
| 24 | mine_weapon | mine-layer turret chip |

Required source art: 25 square icons plus one shared pickup container/frame, rarity border, spawn beam, collection burst, and shadow.

### G. Universal arena terrain

Every stage uses the same arena dimensions and terrain vocabulary. Themes change materials and color treatment, not map category or camera behavior.

Core terrain families:

| ID family | Required assets | Animation/damage |
|---|---|---|
| TERRAIN-GROUND | clean ground plus subtle variation tiles | 8–12 variants/theme |
| TERRAIN-BRICK | intact wall, edges, corners, quadrant pieces, rubble | four-quadrant destruction |
| TERRAIN-STEEL | intact plate, edges, corners, damaged/scorched state | impact feedback |
| TERRAIN-WATER | center, shores, corners, foam | 4-frame surface + wakes |
| TERRAIN-ICE | center, edges, cracks, scuff | shimmer + skid marks |
| TERRAIN-FOLIAGE | center, edges, corners, sparse/dense overlays | rustle + concealment clarity |
| TERRAIN-BOUNDARY | universal arena edge and corner | static |
| TERRAIN-SPAWN | player/enemy spawn pads | telegraph animation |
| TERRAIN-DECAL | tracks, scorch, debris, wet marks, frost | pooled decals |

Four campaign material themes:

1. `frontier`: warm workshop concrete, painted brick, utility metal.
2. `floodplain`: cool wet stone, channels, moss accents, water machinery.
3. `frozen_works`: pale industrial ice, frost, dark steel, blue warning lights.
4. `iron_citadel`: heavy blackened steel, hazard markings, red/orange machinery.

Target source units:

- 4 theme ground sets;
- 4 brick material sets using shared destruction masks;
- 4 steel material sets;
- 1 universal water set with 4 theme-compatible tint profiles;
- 1 universal ice set with theme-compatible tint profiles;
- 4 foliage treatments;
- 1 universal boundary kit;
- 12–20 reusable decals;
- 1 collision/debug grid presentation set for development builds.

### H. Base and objectives

| ID | Asset | States |
|---|---|---|
| BASE-CORE | Original replacement for the protected base objective | healthy, damaged, critical, destroyed |
| BASE-SHIELD | Shield generator field | appearing, active, warning, ending |
| BASE-IMPACT | Hit feedback | armor hit, shield hit, critical alarm |
| BASE-REPAIR | Repair effect | start, active, complete |
| BASE-MARKER | Compact HUD/map identifier | normal, threatened, critical |

The base must not reproduce the original Golden Eagle art or branding. It needs a new original mechanical-core identity.

### I. HUD and touch controls

Gameplay-specific icons are original. SF Symbols may be used only for conventional platform UI actions after license/usage review.

| Family | Required assets |
|---|---|
| HUD-STATUS | lives, armor, speed, power, ammunition, equipment, score |
| HUD-WEAPON | normal plus five special weapon icons |
| HUD-BASE | durability and shield meter |
| HUD-ENEMY | remaining count, wave pressure, elite warning |
| HUD-ALERT | base threatened, low armor, no ammo, pickup explanation |
| INPUT-MOVE | floating stick base, knob, four direction feedback states |
| INPUT-FIRE | normal fire button: idle, pressed, cooldown, disabled |
| INPUT-SPECIAL | special fire button: idle, pressed, cooldown, empty |
| INPUT-EQUIPMENT | equipment/status button if interaction is added; otherwise HUD-only |
| INPUT-PAUSE | pause control |
| HUD-FRAME | scalable panels, separators, meters, compact labels |

Touch controls require original shapes, 44×44-point or larger targets, adjustable opacity, and no opaque critical-information region.

### J. Application screens

| Screen | Required visual assets |
|---|---|
| Launch | app icon, launch background, studio/legal marks as applicable |
| Title | original game logo/wordmark, mechanical arena background, primary call-to-action treatment |
| Campaign | stage cards, completion states, difficulty selectors, checkpoint marker |
| Stage intro | stage name plate, theme plate, enemy composition icons |
| Pause | translucent panel, resume/restart/settings/exit icons |
| Results | victory/defeat plates, score breakdown icons, reward animation |
| Settings | touch, controller, audio, visual, accessibility icons |
| Tutorial | movement, normal fire, special fire, equipment, base-defense illustrations |
| Error/legal | safe plain panels; no decorative art required |

Stage thumbnails must be rendered from actual stage data after presentation is implemented, not independently generated illustrations.

### K. Campaign presentation

- 4 theme key art backgrounds, one per material theme;
- 12 engine-rendered stage thumbnails;
- 3 difficulty emblems;
- 6 enemy weapon-family portraits/icons;
- 4 equipment feature cards;
- 5 special-weapon feature cards;
- 3 onboarding illustrations;
- victory, defeat, campaign-complete, and new-unlock presentation plates;
- optional loading tips using gameplay sprites rather than unique illustrations.

### L. Marketing and store assets

Deferred until the game visual language and title are locked:

- App icon master and required Apple variants;
- store screenshots for required iPhone/iPad sizes;
- App Store promotional artwork if used;
- press-kit logo, transparent key art, and gameplay captures;
- social/banner crops derived from approved key art;
- trailer title/end cards.

Marketing art must be composed from approved game assets or separately approved original key art. It must not promise gameplay views or effects that the game cannot produce.

### M. Audio inventory

Audio is original synthesis/recording/composition or separately commissioned/licensed work.

Music target:

- title/menu theme;
- 4 campaign theme loops;
- high-pressure/finale layer or track;
- victory/result cue;
- defeat cue;
- campaign-complete cue.

Sound-effect families:

- player/enemy engine loops by weight;
- tread on ground, metal, ice, shallow water;
- normal plus five special weapon fire sounds;
- projectile flights/loops where needed;
- armor, shield, brick, steel, water, ice, and foliage impacts;
- four mine levels: place, arm, trigger, explode;
- pickup spawn, hover, collect, replace, reject/cap;
- armor/speed/power/equipment upgrade confirmations;
- tank damage, critical warning, destruction, respawn;
- base shield, damage, critical alarm, destruction, repair;
- enemy spawn, elite warning, freeze, global bomb;
- UI focus, confirm, back, error, pause, results count-up;
- short haptic patterns paired with major player/base events.

No sound extracted from the reference game or another commercial game is permitted in shipping builds without explicit rights.

### N. Technical and production support assets

- neutral checker/debug texture;
- collision and path-cost overlays;
- entity/team ID markers for development builds;
- grayscale and color-vision-deficiency comparison sheets;
- atlas preview images;
- pivot/bounds calibration fixture;
- particle texture primitives;
- shader noise/mask textures created in-house;
- placeholder font and final licensed font records;
- asset provenance ledger;
- attribution/credits data generated from the ledger;
- rejected/obsolete asset archive outside the shipping bundle.

---

## 5. Generation and Finishing Workflow

### Phase 0: style lock

1. Generate the full-arena, tank-family, terrain/effect, and HUD style boards.
2. Select one coherent visual language.
3. Lock camera, silhouette, palette, lighting, material, and contact-shadow rules.
4. Create a non-generated master player tank and one enemy from the approved board through a controlled redraw/cleanup pass.
5. Test them at actual minimum iPhone display size.

### Phase 1: vertical-slice production

Generate and finish:

- player tank modules;
- six enemy archetype representatives;
- all six weapon families;
- all four equipment families;
- base states;
- one complete terrain theme;
- at least 12 pickup icons;
- complete V1 HUD and touch controls;
- enough VFX/audio for three stages.

### Phase 2: campaign production

- complete all 24 enemy combinations;
- complete all 25 pickup icons;
- complete remaining three material themes;
- complete all stage presentation and campaign UI;
- finalize audio and music;
- run consistency, readability, performance, and rights reviews.

### Phase 3: release production

- create final app icon, store media, trailer cards, and press kit;
- remove unused source/prototype assets from the shipping bundle;
- generate final credits/attribution from the provenance ledger;
- archive source masters and license evidence.

---

## 6. Image-Generation Prompt Anchor

Every generated visual in this project must inherit this anchor unless a narrower asset specification explicitly overrides it:

```text
Use case: stylized-concept
Asset type: 2D top-down arcade tank game visual asset
Primary request: original modern mechanical toy arcade design
Style/medium: polished high-definition 2D game illustration; soft modern mechanical tabletop-toy design; crisp production concept art
Composition/framing: strict orthographic top-down view; no horizon; no isometric or three-quarter perspective
Lighting/mood: bright diffuse upper-left key light; short soft contact shadows; welcoming, energetic, and readable, not grim
Color palette: accessible high-contrast player/enemy/weapon-role colors; shape carries meaning in addition to color
Materials/textures: satin enamel-painted metal, rubber tracks, soft molded-plastic accents, restrained seams and edge wear, small emissive strips
Constraints: original design; strong silhouette at small size; no national insignia; no military trademarks; no text; no logos; no watermark
Avoid: photoreal war imagery; realistic gore; copied commercial-game sprites; black-heavy industrial styling; aggressive sharp armor; preschool faces/eyes; candy gloss; pastel washout; excessive surface noise; long shadows; perspective distortion
```

Transparent production sprites add:

```text
Scene/backdrop: genuinely transparent background
Composition/framing: one centered UP-facing asset; complete silhouette; generous transparent padding; no cropping
Constraints: preserve alpha; no floor plane; no background glow beyond the defined effect bounds
```

---

## 7. Provenance Requirements

Each asset record must include:

```text
asset_id
shipping_filename
category
creator_or_generator
generation_prompt_or_brief
source_files
source_url_if_any
license_or_contract
license_evidence_path
creation_or_download_date
modifications
required_attribution
approved_platforms
content_hash
review_status
approved_for_shipping
```

Reference-game screenshots, videos, binaries, extracted sprites, audio, titles, and logos are marked `research_only` and cannot be promoted to `approved_for_shipping` without documented rights approval.

---

## 8. Definition of Done for a Visual Asset

An asset is complete only when:

- it matches the approved visual anchor;
- its gameplay silhouette is readable at minimum iPhone scale;
- pivot, bounds, alpha, color space, and filename are correct;
- it has no accidental text, watermark, logo, or recognizable copied design;
- required states and damage/animation variants exist;
- grayscale and color-vision-deficiency checks pass;
- atlas and memory budgets pass on target hardware;
- the provenance record is complete;
- an art reviewer and gameplay reviewer approve it for shipping.
