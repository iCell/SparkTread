# Project Golden Eagle

## Product, Game Design, and Implementation Plan

Document version: 2.1  
Status: Planning baseline for implementation and external AI review  
Date: 2026-09-01  
Primary stack: Swift + SpriteKit + SwiftUI in the current stable Xcode toolchain  
Primary target: iPhone, landscape orientation  
Secondary targets: iPad, then macOS  
First release mode: single-player only  
Deferred mode: two-player online cooperative play  

---

## 1. Document Contract

### 1.1 Purpose

This document is the implementation authority for **Project Golden Eagle**, a modern single-player 2D top-down tank-defense action game inspired by the design strengths of the early-2000s Chinese PC game *决战坦克 v1.2.2*. The architecture must permit a later two-player online cooperative mode without requiring a rewrite of authoritative combat rules.

It is written so that a human developer or an AI coding agent can:

1. understand the intended game without relying on prior conversation;
2. identify what is fixed, tunable, deferred, or unresolved;
3. implement one subsystem without inventing incompatible architecture;
4. validate the work using explicit acceptance criteria;
5. hand work to another agent with minimal context loss;
6. review the plan for contradictions, missing requirements, and delivery risk.

This is not a claim that the new game will be a byte-identical recreation. The original game is a research reference. The product goal is a stronger modern game that preserves its most distinctive ideas.

### 1.2 Normative language

- **MUST**: required for compatibility with this plan.
- **MUST NOT**: prohibited because it breaks architecture, scope, or product intent.
- **SHOULD**: expected unless an Architecture Decision Record explains the exception.
- **MAY**: optional and safe to omit.
- **PROVISIONAL**: a working value that must be playtested before content lock.
- **DEFERRED**: intentionally outside the current milestone.

### 1.3 Source-of-truth order

When documents conflict, use this order:

1. this document and accepted Architecture Decision Records;
2. `GAME_MECHANICS_SPEC.md` for facts about the reference game;
3. `STAGE_52_METADATA.csv` for recovered candidate reference-stage metadata;
4. automated tests and checked-in content schemas;
5. issue descriptions, agent prompts, comments, and informal notes.

Reference-game data does not override an explicit modern-product decision in this document.

### 1.4 Required companion material

- `DOCUMENT_INDEX.md`: reading order, authority order, and current fixed-direction index.
- `GAME_MECHANICS_SPEC.md`: evidence-graded reference-mechanics research.
- `STAGE_52_METADATA.csv`: 52 candidate reference-stage metadata records.
- `PROJECT_MASTER_SUMMARY_ZH.md`: Chinese consolidated summary of all currently confirmed product and implementation decisions.
- `ASSET_PRODUCTION_MANIFEST.md`: complete visual/audio inventory, art direction, production method, and provenance requirements.
- `ASSET_REQUIREMENTS_LIST_ZH.md`: enumeration-only Chinese checklist of every required shipping asset family; it does not authorize generation.
- `AI_REVIEW_PROMPT.md`: a reusable prompt for external plan review.

### 1.5 Decision changes

An implementation agent MUST NOT silently reinterpret a fixed decision. A proposed change must be recorded as an ADR in `docs/decisions/ADR-NNNN-short-name.md` with:

- context;
- decision;
- alternatives considered;
- gameplay consequences;
- architecture consequences;
- migration cost;
- tests affected.

Until an ADR is accepted, this document remains authoritative.

### 1.6 Version 2.0 change record

Version 2.0 supersedes the former Godot/macOS-first/local-co-op plan. It fixes the following product direction:

- Apple-native Swift + SpriteKit + SwiftUI implementation;
- iPhone landscape first, then iPad and macOS;
- one universal modern arena class rather than classic/standard/large map categories;
- fixed 2D top-down full-map presentation with every active tank visible;
- device-independent world units rather than a required 640×480 product viewport;
- V1 single-player only;
- future exactly-two-player online co-op enabled by stable IDs, tick commands, snapshots, and determinism—not by shipping networking code early;
- one modern shipping ruleset, with the original game retained as research evidence.

### 1.7 Version 2.1 change record

Version 2.1 locks the approved visual direction as **Soft Modern Mechanical Toy Arcade** and adds a consolidated Chinese master summary plus an enumeration-only asset checklist. It does not authorize or perform bulk asset generation.

---

## 2. Executive Product Definition

### 2.1 One-sentence pitch

**A readable, fast, single-player 2D top-down tank-defense action game in which the player protects a vulnerable base through destructible terrain, specialized weapons, equipment, and complete battlefield awareness.**

### 2.2 Product identity

Project Golden Eagle is a **spiritual successor**, not a generic Battle City clone and not a museum-perfect emulator. Its identity comes from the combination of:

- protecting a Golden Eagle-style base while eliminating a finite enemy force;
- independent normal-fire and special-fire channels;
- independent armor, speed, power, weapon, ammunition, and equipment progression;
- equipment-specific terrain traversal;
- meaningful mine, fire, armor-piercing, and explosion interactions;
- enemies that actively pressure the base;
- a single unified class of dense, hand-authored, single-screen battlefield;
- a fixed full-map view in which every active tank remains visible;
- a command-driven simulation that can later accept a second online player's input.

### 2.3 Intended player experience

The player should repeatedly experience this loop:

1. read the battlefield and enemy composition;
2. establish safe firing lanes and protect the base;
3. react to terrain damage and enemy breakthroughs;
4. acquire an upgrade that changes tactical options;
5. combine weapon, equipment, positioning, and route-control choices;
6. recover from a dangerous base-defense crisis;
7. finish the stage with a clear, earned victory.

### 2.4 Design pillars

#### PILLAR-01: Immediate control, tactical consequences

Movement and firing must feel responsive within seconds, but weapon choice, terrain destruction, and positioning must have consequences.

#### PILLAR-02: The base creates pressure

Enemies do not exist only to chase players. The base forces prioritization, interception, and emergency defense.

#### PILLAR-03: Complete battlefield awareness

The complete map and every active tank remain visible throughout play. Difficulty comes from reading simultaneous threats, prioritizing routes, and choosing tools—not from off-screen attacks or camera management.

#### PILLAR-04: Power is visible and understandable

Every upgrade and dangerous enemy action should have a readable visual, audio, and HUD signal.

#### PILLAR-05: Depth from interaction, not input complexity

The core control scheme remains four-direction movement plus normal fire and special fire. Depth comes from interacting systems rather than a large button vocabulary.

### 2.5 Target audience

- players who remember arcade tank-defense games;
- iPhone players seeking short, replayable action sessions;
- players who prefer short, replayable action stages;
- players who enjoy tactical weapons without complex character builds.

### 2.6 Session targets

| Context | Target duration |
|---|---:|
| First useful interaction | under 15 seconds from title screen |
| Individual stage | 6–10 minutes |
| Three-stage vertical-slice run | 20–30 minutes |
| Twelve-stage campaign | 90–120 minutes with between-stage checkpoints |
| Challenge run | 15–40 minutes |

---

## 3. Scope

### 3.1 First public-quality campaign scope

The first campaign MUST contain:

- 12 hand-authored stages using one universal arena specification across 4 visual/terrain themes;
- single-player only;
- 5 special weapon families;
- 4 equipment families;
- all 24 reference-derived enemy archetype slots, with modern campaign tuning;
- a representative subset of reference-inspired pickups plus any approved new pickups;
- 3 campaign difficulty presets;
- checkpoint saving between stages;
- first-class iPhone touch controls;
- supported Apple game controllers, plus keyboard controls on iPad/macOS where available;
- remappable controls;
- pause, restart, accessibility, audio, and display options;
- stage results and campaign progression;
- original replacement art and audio suitable for distribution.

### 3.2 Vertical-slice scope

The vertical slice MUST contain:

- 3 complete stages: onboarding, combined-arms, and crisis/finale;
- one terrain theme with brick, steel, water, ice, and foliage represented across the slice;
- one local player controlled by touch or an assigned controller;
- normal fire plus all 5 special weapon families;
- all 4 equipment families;
- at least 6 enemy archetypes, one from each weapon family;
- enemy spawning, finite stage composition, base pressure, win, loss, restart, and results;
- 12 or more pickup effects, including weapon switching, ammunition, armor, speed, power, base shield, freeze, bomb, and extra life;
- one elite encounter that forces deliberate weapon/equipment switching;
- final-quality control feel, provisional art, and representative audio;
- deterministic replay tests for the entire three-stage run.

### 3.3 Explicit non-goals for the vertical slice

- online multiplayer;
- local multiplayer;
- all 12 campaign stages;
- procedural level generation;
- user-generated maps;
- a persistent grind or monetized progression economy;
- a full narrative campaign;
- perfect recreation of every original timing constant;
- shipping original copyrighted sprites, title art, music, or branding.

### 3.4 Deferred possibilities

- two-player online co-op using a host-authoritative or server-authoritative model selected through a later ADR;
- spectator support;
- endless defense;
- daily seeded challenge;
- user map editor;
- Windows and Android ports;
- additional weapons, equipment, bosses, and biomes;
- lightweight cosmetic or starting-loadout unlocks;
- Steam Deck and console certification.

---

## 4. Fixed Product Decisions

| ID | Decision | Status |
|---|---|---|
| D-001 | The project is a spiritual successor with new distributable art, audio, title, and branding. | Fixed |
| D-002 | Swift, SpriteKit, and SwiftUI in the current stable Xcode toolchain are the implementation baseline. | Fixed for project initialization |
| D-003 | All shipping stages use one universal fixed-size, approximately 16:9 arena. The initial implementation baseline is 48×27 base terrain cells; M1 may tune this once through an ADR before combat content is authored. | Fixed type; provisional dimensions |
| D-004 | Gameplay is 2D top-down. The complete arena and every active tank remain visible at all times; there is no camera follow, scrolling, gameplay zoom, or split-screen. | Fixed |
| D-005 | Simulation runs at a fixed 60 Hz tick using integer or fixed-point state. Rendering may interpolate. | Fixed |
| D-006 | Core input is four-direction movement, normal fire, and special fire. | Fixed |
| D-007 | V1 ships as single-player only. Local multiplayer, split-screen, and networking are not implemented in V1. | Fixed |
| D-008 | Authoritative state and commands use stable `PlayerID` values and support a future capacity of two players; V1 creates only one player. | Fixed |
| D-009 | The modern ruleset is authoritative and may intentionally improve on the reference game. Reference behavior is research evidence, not a second shipping mode. | Fixed |
| D-010 | Allied damage to the player's own base is disabled unless an explicit modern gameplay rule later enables a clearly telegraphed exception. | Fixed |
| D-011 | The first campaign contains 12 handcrafted stages; the vertical slice contains 3. | Fixed |
| D-012 | Gameplay rules MUST NOT be implemented inside HUD, animation, audio, or scene scripts. | Fixed |
| D-013 | Content is canonical in reviewable text files and validated before play. | Fixed |
| D-014 | Agents MUST preserve determinism and must not use frame-rate-dependent gameplay logic. | Fixed |
| D-015 | No original binary or extracted asset may be committed to the distributable game without confirmed rights. | Fixed |
| D-016 | Device adaptation uses uniform scaling and safe-area-aware UI; device aspect ratio MUST NOT reveal or hide playable terrain. | Fixed |
| D-017 | SpriteKit and SwiftUI are presentation/platform adapters. Authoritative rules live in a pure Swift `GameCore` module and MUST NOT import SpriteKit, SwiftUI, GameKit, AVFoundation, or platform UI APIs. | Fixed |
| D-018 | Future online play consumes the same tick-addressed command API as local input. V1 implements replay/determinism foundations but no speculative networking layer or unused transport interface. | Fixed |
| D-019 | Shipping art uses the approved Soft Modern Mechanical Toy Arcade direction: moderately rounded silhouettes, large color panels, satin enamel and soft molded-plastic accents, restrained mechanical detail, strict top-down readability, and no faces/eyes or preschool styling. | Fixed |
| D-020 | The soft v2 arena and tank-family styleboards are visual references, not shipping sprite sheets. Production assets require separate extraction/redraw, technical normalization, readability review, and provenance approval. | Fixed |

The repository MUST record the exact Xcode and Swift toolchain used for release builds. Toolchain upgrades require the complete automated regression suite and an ADR when they change build settings, language mode, serialization, timing, or runtime behavior.

---

## 5. Game Modes and Rulesets

### 5.1 Campaign

This is the default product experience.

- Three difficulty presets: Casual, Standard, Veteran.
- Base has visible durability instead of universal one-hit failure.
- Allied friendly fire is disabled.
- Enemy special attacks receive clearer telegraphs.
- Upgrade effects are named and previewed.
- Previous special-weapon ammunition is retained when switching away and returning later.
- Stage selection is understandable; stages are not hidden only behind the hardest difficulty.
- Difficulty focuses on composition, tactical behavior, and pressure, not only raw speed and ammunition.
- Checkpoints save after every completed stage.

There is one shipping ruleset. Reference-derived values may seed tuning, but there is no separate reference/classic player-facing mode.

### 5.2 Training Arena

The training arena SHOULD be available before campaign completion and MUST support:

- spawning selected enemies;
- granting any weapon/equipment/upgrade;
- toggling invulnerability;
- showing collision shapes and path costs in development builds;
- testing terrain and mine interactions;
- recording deterministic input replays.

### 5.3 Future Two-Player Online Co-op

Two-player online co-op is DEFERRED until the V1 campaign is stable. It will:

- use the same fixed arena and full-map camera;
- support exactly two active player-controlled tanks;
- send tick-addressed `PlayerCommand` values into the same `GameCore` command boundary;
- use stable `PlayerID` ownership for tanks, pickups, score, respawn, and results;
- scale enemy composition and pacing through mode data rather than branching combat code;
- choose matchmaking, transport, authority, prediction, rollback, reconnect, and host-migration policies in a dedicated pre-network ADR.

V1 MUST NOT ship dormant sockets, matchmaking code, a generic `NetworkManager`, or an unused network abstraction. The V1 obligation is deterministic command simulation, snapshots, checksums, and multi-player-capable data identifiers.

### 5.4 Future Challenge Mode

Challenge mode is DEFERRED until the campaign loop is stable. It may reuse campaign stages with fixed loadouts, mutators, time targets, or seeded enemy waves.

---

## 6. Core Gameplay Specification

### 6.1 Coordinate system

- World origin: top-left.
- Positive X: right.
- Positive Y: down.
- Arena bounds use integer or fixed-point world units, never device pixels or SpriteKit points.
- Initial base grid: 48×27 terrain cells; X `0..47`, Y `0..26`; PROVISIONAL until the M1 legibility gate.
- One base terrain cell: `1024` simulation subunits per side.
- Standard tank footprint: 2×2 base cells; collision inset is PROVISIONAL.
- Terrain destruction subcell: half-cell quadrants, allowing four destructible quadrants per base cell.
- All stage definitions MUST use the same final arena dimensions.
- Rendering computes one uniform scale using `min(availableWidth / arenaWidth, availableHeight / arenaHeight)` and never stretches one axis independently.

### 6.2 Direction convention

```text
0 = UP    vector ( 0, -1)
1 = RIGHT vector ( 1,  0)
2 = DOWN  vector ( 0,  1)
3 = LEFT  vector (-1,  0)
```

Opposite direction is `(direction + 2) % 4`.

### 6.3 Player controls

The V1 player has these required actions:

- move up;
- move right;
- move down;
- move left;
- normal fire;
- special fire;
- confirm;
- pause/back.

Modern control behavior:

- A direction pressed shortly before a legal turn MUST be buffered.
- Near a corridor centerline, the tank SHOULD receive limited orthogonal alignment assistance.
- Assistance MUST NOT teleport through collision or change tactical speed.
- When opposite directions are pressed together, the most recently pressed direction wins.
- Digital keyboard and D-pad behavior must be deterministic.
- Analog stick input is quantized to four directions using hysteresis to avoid direction flicker.

Input-buffer and alignment values are tuning parameters, not hardcoded constants.

### 6.4 Player state

```text
PlayerState
  player_id: stable integer (V1 uses 1; future online capacity is 2)
  active: bool
  lives: int
  score: int
  tank_entity_id: int | null
  life_state: active | awaiting_respawn | eliminated
  special_ammo_by_weapon: map<weapon_id, int>
  last_checkpoint_state

WorldState
  players: map<PlayerID, PlayerState> # capacity 2; V1 runtime contains only player 1

TankState
  entity_id: int
  team_id: int
  owner_player_id: PlayerID | null
  archetype_id: string
  position_subpx: Vec2i
  facing: Direction
  movement_intent: Direction | none
  armor: int
  max_armor: int
  speed_level: int
  power_level: int
  special_weapon_id: string
  equipment_id: string
  status_effects: map<status_id, remaining_ticks>
  fire_cooldowns: map<channel, remaining_ticks>
  active_projectile_counts: map<weapon_id, int>
  spawn_protection_ticks: int
```

Campaign starting values, PROVISIONAL:

| Field | Value |
|---|---:|
| Lives per player | 3 |
| Armor | 3 of 8 |
| Speed level | 0 of 3 |
| Power level | 0 of 3 |
| Initial special weapon | Rapid |
| Initial Rapid ammunition | 50 |
| Spawn protection | 120 ticks / 2 seconds |

The app, HUD, and touch adapters MUST NOT expose a second-player activation path in V1. A core-only automated fixture MUST be able to instantiate player IDs 1 and 2 and feed two command streams; this proves data-model readiness without shipping multiplayer.

### 6.5 Player death and re-entry

1. When armor reaches zero, the active tank is destroyed.
2. If the player has another life, consume one life and schedule respawn after 60 ticks.
3. On campaign respawn, retain speed level, power level, equipment, selected special weapon, and stored special ammunition; reset armor to the configured respawn armor.
4. Respawn protection is visible and prevents damage, but does not permit passing through solid terrain.
5. If no life remains, the player becomes eliminated.
6. A `+1UP` pickup adds one life according to campaign rules; V1 does not revive a second player.
7. The stage is lost when the base is destroyed or the sole player is eliminated with no pending revival.

The exact retention policy is campaign ruleset data so later cooperative balancing can differ without branching combat systems.

### 6.6 Base rules

Campaign base behavior:

- Base maximum durability: 3; PROVISIONAL.
- Any unblocked damaging hit reduces durability according to weapon data.
- Damage states are visually distinct at 3, 2, 1, and 0 durability.
- Base shield prevents damage for a configured duration and MUST be visually obvious.
- A shield pickup refreshes short remaining duration and extends long remaining duration according to ruleset data.
- Base-adjacent terrain may be destroyed and repaired by explicit effects.
- The base does not fire or move in the first campaign.

### 6.7 Win and loss

- Win: no scheduled enemy remains, no enemy is alive or spawning, and the base is alive.
- Loss: base durability reaches zero, or the V1 player is eliminated with no pending revival.
- Win/loss is resolved after all damage and death events for the current tick.
- Simultaneous destruction is ruleset-defined; the campaign defaults to loss if the base reaches zero on the same tick as the last enemy.

### 6.8 Stage pacing

- The V1 player enters before enemies.
- Default enemy-start delay: 240 ticks / 4 seconds.
- Enemy spawn locations are stage-defined.
- `max_alive_enemies` limits simultaneous pressure.
- EnemyDirector draws from finite per-archetype counts.
- New enemies must telegraph their spawn for at least 45 ticks before becoming dangerous; PROVISIONAL.
- Spawn protection or collision separation MUST prevent unavoidable spawn kills.

---

## 7. Movement and Terrain

### 7.1 Movement model

- Tanks move only along cardinal axes.
- Position uses integer subpixels with `256 subpixels = 1 logical pixel`.
- Movement distance per tick is calculated with an integer accumulator to avoid drift.
- Simulation MUST NOT multiply movement by variable `_process(delta)`.
- Tank-vs-terrain and tank-vs-tank collision resolution MUST be deterministic.
- A tank may turn only when the new movement vector is collision-free after permitted alignment assistance.

### 7.2 Campaign speed levels

Initial tuning should start from the known reference multipliers:

| Level | Multiplier |
|---:|---:|
| 0 | 1.000 |
| 1 | 1.260 |
| 2 | 1.588 |
| 3 | 2.000 |

The base pixels-per-second value is PROVISIONAL and must be selected in the Movement Lab milestone. The multiplier curve should not change before measurement shows a control or balance problem.

### 7.3 Terrain types

| Terrain | Blocks tanks | Blocks shots | Destructible | Special behavior |
|---|---|---|---|---|
| Ground | No | No | No | Default movement |
| Brick | Yes | Yes | Yes, by 8×8 quadrant | Damage mask changes collision |
| Steel | Yes | Yes | By qualified weapons/levels | High resistance |
| Water | Yes by default | No | No | AmphiTank permits traversal and water mines |
| Ice | No | No | No | Adds inertia/turning friction unless AntiSkid |
| Foliage | No | No by default | Optional | Occludes tanks/projectiles visually |
| Dark/snow decorative ground | No | No | No | Presentation variation |
| Base | Yes | Yes | Objective | Team and shield rules |

### 7.4 Destructible terrain

- A 16×16 brick/steel cell stores a four-bit quadrant mask.
- A projectile collision computes impacted quadrants from impact point, direction, radius, and weapon terrain damage.
- Collision geometry updates in the same simulation tick as damage.
- Rendering consumes `TerrainChanged` events and MUST NOT own the authoritative mask.
- Explosion damage may affect multiple adjacent subcells using a deterministic scan order.

### 7.5 Equipment traversal

- `AmphiTank` selects the amphibious passability profile.
- `AntiSkid` selects the traction passability/movement profile.
- `ShieldOfMoon` and `MemoryOfSea` retain normal terrain passability unless ruleset data specifies otherwise.
- AI and players MUST use the same terrain legality rules.

---

## 8. Weapons

### 8.1 Fire channels

#### Normal channel

- Always available while a tank is active.
- Does not consume special ammunition.
- Has its own cooldown and active-projectile limit.
- Remains useful for normal enemies and brick destruction.

#### Special channel

- Uses the currently equipped special weapon.
- Consumes ammunition according to weapon data.
- If ammunition is zero, the input produces a dry-fire event and no projectile.
- Switching weapon does not erase stored ammunition in the campaign.

### 8.2 Required weapon families

| ID | Role | Modern campaign identity |
|---|---|---|
| `normal` | Reliable baseline | Unlimited, accurate, moderate cooldown |
| `rapid` | Suppression/interception | Very fast shots, high rate, modest per-hit force |
| `fire` | Short-range area denial | Short-lived flame, lingering danger, strong lane control |
| `ap` | Armor/line penetration | Starts slow, accelerates, penetrates qualified targets |
| `explosion` | Area and terrain control | Accelerates, detonates in an area, triggers qualified mines |
| `mine` | Trap and route control | Persistent placed hazard with level-specific visibility/effects |

### 8.3 Reference-derived ammunition bases

| Weapon | Pickup refill | Carry cap |
|---|---:|---:|
| Rapid | 50 | 250 |
| Fire | 30 | 150 |
| AP | 10 | 50 |
| Explosion | 20 | 100 |
| Mine | 15 | 75 |

The campaign SHOULD begin with these values and tune only after ammunition-economy playtests.

### 8.4 Weapon data contract

Every weapon definition MUST provide per-power-level arrays with exactly four entries:

```text
WeaponDefinition
  id: string
  family: normal | rapid | fire | ap | explosion | mine
  fire_channel: normal | special
  ammo_cost: int
  refill_amount: int
  max_ammo: int
  cooldown_ticks[4]: int
  max_active[4]: int
  initial_speed_subpx_per_tick[4]: int
  acceleration_subpx_per_tick2[4]: int
  max_speed_subpx_per_tick[4]: int
  lifetime_ticks[4]: int
  tank_damage[4]: int
  brick_damage[4]: int
  steel_damage[4]: int
  projectile_durability[4]: int
  penetration_count[4]: int
  explosion_radius_subpx[4]: int
  mine_trigger_radius_subpx[4]: int
  status_effect_id: string | null
  friendly_fire_policy: string
  presentation_id: string
```

The simulation MUST NOT branch on display names or sprite names.

### 8.5 Collision categories

The weapon rules matrix MUST explicitly cover:

- projectile vs enemy tank;
- projectile vs allied tank;
- projectile vs base;
- projectile vs brick quadrant;
- projectile vs steel quadrant;
- projectile vs projectile;
- projectile vs mine;
- explosion vs every category above;
- fire hazard vs each team;
- mine vs tank with each equipment type.

An unlisted collision is a content-validation failure, not an implicit no-op.

### 8.6 Mines and equipment

Required interactions:

- AmphiTank allows mines to be placed on water.
- AntiSkid safely crosses enemy mines of levels 0–2.
- Level-3 mines have a distinct ring and are not covered by that immunity.
- Shield of Moon safely removes enemy level-0 mines.
- Memory of Sea prevents post-survival launch/flight and slow effects, but does not grant damage immunity.
- Explosion weapons detonate mines with level less than or equal to explosion power level.
- Friendly-mine behavior is ruleset data.

### 8.7 Fire team filtering

The simulation supports three fire-hazard filters:

- damages both teams;
- damages player/allied team only;
- damages enemy team only.

Campaign player fire defaults to enemy-only. Enemy fire defaults to player-only unless a stage mutator intentionally creates neutral red fire.

---

## 9. Equipment and Upgrades

### 9.1 Equipment slot

Each tank has one equipment slot:

- `none`;
- `amphi_tank`;
- `anti_skid`;
- `shield_of_moon`;
- `memory_of_sea`.

Collecting different equipment replaces the active equipment. The campaign displays the incoming equipment name and current replacement clearly.

### 9.2 Independent upgrade axes

- `armor`: 0..8;
- `speed_level`: 0..3;
- `power_level`: 0..3;
- selected special weapon;
- stored special ammunition per weapon;
- active equipment;
- timed status effects.

No implementation may collapse these values into one generic tank level.

### 9.3 Pickup behavior

- Pickups are simulation entities with deterministic positions and lifetimes.
- A pickup spawned overlapping a tank must allow an avoidance/grace period before collection; campaign default 45 ticks / 0.75 seconds, PROVISIONAL.
- Pickup identity and effect must be visually readable before collection where practical.
- Collection is processed after movement and damage for the tick.
- Score-only pickups cannot be collected by enemies.
- An enemy with Memory of Sea may collect allowed non-score pickups if the active ruleset enables the reference behavior.

### 9.4 Required vertical-slice pickups

| Stable ID | Effect |
|---|---|
| `speed_up` | Increase speed level |
| `armor_up` | Restore/increase armor |
| `power_up` | Increase power level |
| `level_up` | Increase multiple upgrade axes |
| `max_speed_power` | Maximize speed and power |
| Four equipment pickups | Replace equipment |
| `invincibility` | Timed damage immunity |
| `base_shield` | Timed base protection |
| `freeze_enemies` | Timed enemy hold |
| `bomb` | Damage/destroy qualified active enemies |
| `extra_life` | Add/reactivate a player life |
| `max_armor_ammo` | Max armor and current special ammunition |
| `ammo` | Refill current special weapon |
| Five weapon pickups | Switch and refill the selected weapon |

Score pickups may be added during the results/score milestone.

---

## 10. Enemies and AI

### 10.1 Enemy content model

The complete campaign supports 24 base archetypes arranged as:

```text
6 weapon families × 4 variants
```

Variants differ by:

- armor;
- speed level;
- power level;
- equipment;
- special ammunition;
- score/reward class;
- visual silhouette or palette;
- AI behavior weights.

The reference-derived attribute table in `GAME_MECHANICS_SPEC.md` is the starting dataset, not an untouchable modern balance requirement.

### 10.2 AI architecture

AI is divided into two responsibilities:

#### EnemyDirector

- owns finite stage composition and spawn budget;
- respects `max_alive_enemies`;
- selects legal spawn points;
- controls pressure pacing and elite timing;
- never directly moves or fires a tank.

#### EnemyBrain

- receives a read-only world query and its tank state;
- selects a tactical target and behavior state;
- emits the same `TankCommand` shape used by a player;
- never changes world state directly.

### 10.3 Required behavior states

```text
Spawn
Advance
AttackPlayer
AttackBase
BreakTerrain
LayMine
SeekPickup
Retreat/Reposition
Stunned/Frozen
```

Not every archetype needs every state.

### 10.4 Navigation

- Navigation works on deterministic grid cost maps.
- At minimum, normal, amphibious, and anti-skid cost profiles exist.
- Terrain destruction invalidates affected navigation regions.
- Path choice uses deterministic tie breaking derived from the stage RNG.
- AI may use short local steering to align shots but may not bypass tank collision.
- Recalculation is budgeted; every enemy does not need a full path search every tick.

### 10.5 Tactical target selection

Target score SHOULD combine:

- base threat opportunity;
- distance/path cost;
- line of fire;
- nearby player threat;
- current weapon suitability;
- stage-authored tactical bias;
- difficulty profile;
- recent target persistence to reduce erratic switching.

### 10.6 Readability and fairness

- AP, Explosion, Fire, and Mine threats must have distinct telegraphs.
- Dangerous enemies must be recognizable before they fire.
- AI may predict movement on Veteran but MUST NOT read future player input.
- Enemy spawn positions must not produce unavoidable immediate base damage.
- Difficulty must not increase speed beyond collision reliability.

### 10.7 Campaign difficulty profiles

| Dimension | Casual | Standard | Veteran |
|---|---:|---:|---:|
| Targeted behavior | Low | Medium | High |
| Base focus | Low | Medium | High but interruptible |
| Special ammo | 70% | 100% | 140% |
| Reaction interval | Long | Normal | Short |
| Coordinated role behavior | Rare | Occasional | Frequent |
| Telegraph duration | Long | Normal | Never below fairness floor |
| Enemy composition | Forgiving | Authored baseline | More advanced variants |

Exact numbers live in `DifficultyDefinition`; the table defines intent.

---

## 11. Level and Campaign Design

### 11.1 Stage data

```text
StageDefinition
  schema_version: int
  id: string
  display_name_key: string
  theme_id: string
  arena_width_cells: 48  # provisional until M1 gate; then universal
  arena_height_cells: 27 # provisional until M1 gate; then universal
  terrain_layers: array
  base_spawn: GridPos
  player_spawns_by_id: map<PlayerID, GridPos> # V1 activates only player 1
  enemy_spawns: array<SpawnPoint>
  enemy_counts: map<enemy_archetype_id, int>
  max_alive_enemies: int
  initial_enemy_delay_ticks: int
  pickup_spawns: array
  hidden_pickups: array
  stage_mutators: array<string>
  intro_text_key: string
  tutorial_steps: array
  music_cue_id: string
  par_time_ticks: int | null
```

### 11.2 Stage design rules

- Every stage must offer at least two meaningful routes between player area and enemy area.
- The base must be threatened, but not by an unavoidable straight shot at enemy activation.
- Destructible terrain should create changing routes rather than only decoration.
- Water and ice must change tactics when present.
- Foliage must not hide lethal information without a readable cue.
- Hidden pickups should be learnable through visual language, not arbitrary pixel hunting.
- The stage must remain completable if all destructible terrain is removed.
- The reserved future player-2 spawn must not trap either player or create a safer route unavailable to player 1.
- Enemy composition must exercise the terrain and pickup opportunities of the map.
- The complete arena and every active tank must remain visible at the minimum supported iPhone viewport.
- Stages MUST NOT depend on camera scrolling, off-screen spawns, or attacks whose source cannot be seen.

### 11.3 Three-stage vertical slice

#### VS-01: First Defense

Purpose: teach movement, normal fire, base defense, brick destruction, and pickups.

- Primarily Normal and Rapid enemies.
- Safe initial base wall.
- One visible Speed or Power pickup.
- One controlled breakthrough that teaches interception.
- Target duration: 6 minutes.

#### VS-02: Split Current

Purpose: teach equipment, water/ice, weapon switching, and route prioritization.

- Water route that strongly rewards AmphiTank.
- Ice lane that rewards AntiSkid.
- Fire and Mine enemies.
- Two simultaneous threats create a readable solo prioritization decision with a recoverable response window.
- Target duration: 8 minutes.

#### VS-03: Eagle Under Siege

Purpose: validate the full combat system and crisis recovery.

- AP and Explosion enemies.
- Elite wave with a protected mine-layer or terrain breaker.
- Base shield/repair opportunity before final pressure.
- Multiple destructible approaches.
- Target duration: 10 minutes.

### 11.4 Twelve-stage campaign structure

| Theme | Stages | Learning goal |
|---|---:|---|
| Frontier | 1–3 | Core movement, base defense, Normal/Rapid |
| Floodplain | 4–6 | Water, AmphiTank, Fire, route control |
| Frozen Works | 7–9 | Ice, AntiSkid, mines, visibility |
| Iron Citadel | 10–12 | Steel, AP, Explosion, combined elite pressure |

Stage 12 should be a multi-phase commander encounter implemented using ordinary simulation rules plus authored director phases, not a separate incompatible boss engine.

---

## 12. UX, HUD, and Presentation

### 12.1 Screen flow

```text
Boot
  -> Title
  -> Campaign / Stage Select
  -> Input Selection when more than one supported device is connected
  -> Stage Intro
  -> Gameplay
  -> Pause (overlay)
  -> Stage Results
  -> Next Stage / Retry / Exit
```

### 12.2 HUD requirements

The V1 player panel shows:

- lives;
- armor and maximum armor;
- speed level;
- power level;
- current special weapon;
- current and maximum special ammunition;
- equipment;
- score;
- timed invincibility/status indicator.

Shared HUD shows:

- base durability and shield duration;
- enemies remaining;
- active wave/pressure cue where applicable;
- stage title;
- temporary pickup explanation;
- pause and input-device status when relevant.

The HUD layout must be data-driven by player count. V1 renders one player panel with no empty player-2 placeholder; future online co-op may render a second compact panel without changing `GameCore` snapshots.

### 12.3 Readability rules

- Team identity must not rely on color alone.
- Mine level and ownership must be distinguishable by shape/ring/animation.
- Invulnerability, base shield, freeze, and equipment must have unique silhouettes or effects.
- HUD text must remain readable at the minimum supported window size.
- Screen shake, flashes, and particles must have intensity options.
- Destructive terrain state must match collision state on the same rendered frame after event consumption.

### 12.4 Audio rules

- Normal and five special weapons have distinguishable attack sounds.
- Empty special ammunition has a quiet dry-fire sound with cooldown to avoid spam.
- Base damage has priority over routine weapon sounds.
- Foliage-obscured or visually dense dangerous attacks need spatial or UI audio cues.
- Audio buses: Master, Music, SFX, UI, Ambience.
- No gameplay logic may depend on audio completion.

### 12.5 Accessibility baseline

- first-class touch controls with adjustable size, position, handedness, and opacity;
- supported game-controller remapping where the platform permits it;
- keyboard remapping on iPad/macOS where available;
- separate screen shake, flash, and vibration controls;
- color-blind-safe team and mine cues;
- adjustable HUD scale;
- pause during V1 single-player;
- optional aim/turn alignment assistance;
- readable pickup descriptions;
- three difficulty presets plus independent assists where practical.

### 12.6 Approved visual direction

The fixed style name is **Soft Modern Mechanical Toy Arcade**.

- Shapes are compact and moderately rounded, with broad tracks and immediately readable weapon silhouettes.
- Surfaces use satin enamel-painted metal and small soft molded-plastic accents.
- Large simple color panels replace black-heavy armor, dense rivets, hard bevels, grime, and aggressive seams.
- The palette favors blue/cyan for the player and warm cream, amber, sage, muted coral, lavender, and warm charcoal for enemy roles.
- The presentation is playful and welcoming but MUST NOT become preschool-like, candy-glossy, plush, face-bearing, or visually washed out.
- Strict orthographic top-down projection and minimum-iPhone readability override decorative detail.
- The approved visual references are `styleboards/golden_eagle_arena_styleboard_v2_soft.png` and `styleboards/golden_eagle_tank_family_styleboard_v2_soft.png`.

### 12.7 Asset-source policy

- Reference-game screenshots, videos, manuals, binaries, extracted sprites, audio, names, and logos are research-only unless documented rights explicitly permit shipping use.
- Shipping gameplay art, branding, music, and key sound effects must be original, commissioned, or individually license-approved.
- Prototype third-party assets must have recorded source and license evidence; approval for prototyping does not imply approval for shipping.
- Every shipping asset requires a provenance record and must satisfy `ASSET_PRODUCTION_MANIFEST.md`.
- `ASSET_REQUIREMENTS_LIST_ZH.md` is an inventory only. Listing an asset does not authorize generation, acquisition, purchase, or inclusion.

---

## 13. Technical Architecture

### 13.1 Dependency rule

Dependencies point inward:

```text
SwiftUI App / SpriteKit / Touch / Controller / Audio / Persistence
                              |
                              v
                  Application / Session
                              |
                              v
                    Pure Swift GameCore
                              |
                              v
                    Domain Models and Rules
```

The domain layer MUST NOT import or access:

- `SpriteKit`, `SwiftUI`, `GameKit`, `GameController`, `AVFoundation`, or UIKit/AppKit view types;
- `SKScene`, `SKNode`, `SKPhysicsWorld`, `SpriteView`, or texture/asset identifiers;
- filesystem APIs;
- window/display APIs;
- wall-clock time;
- nondeterministic global random calls.

It MAY use Swift standard-library and Foundation value types whose behavior is explicitly normalized for determinism and serialization. Authoritative vectors, timers, and IDs must be project-owned value types.

### 13.2 Interface ownership

Interfaces or abstract protocols are defined by the consumer that needs them, with only the required methods. Do not create generic `ports/`, `interfaces/`, or `contracts/` directories.

Examples:

- Session orchestration defines the narrow persistence operations it needs.
- EnemyBrain defines the read-only world-query operations it needs.
- Presentation defines the snapshot/event feed it consumes.
- Save adapters implement session-owned requirements.

### 13.3 Simulation state versus presentation state

Authoritative simulation state includes:

- positions and facing;
- armor, upgrades, ammunition, equipment, status timers;
- projectiles, mines, pickups, terrain masks;
- enemy composition and spawn timers;
- base state;
- RNG state;
- stage objective state.

Presentation-only state includes:

- animation frame;
- particles;
- screen shake;
- floating text;
- sound playback handles;
- viewport layout and presentation interpolation;
- menu transitions.

Presentation may read snapshots and events. It must never decide damage, collection, death, terrain collision, or victory.

### 13.4 Deterministic RNG

- Each stage starts from an explicit 64-bit seed.
- Simulation owns one or more named RNG streams, such as `ai`, `spawn`, and `drop`.
- Stream order is stable and tested.
- Cosmetic randomness uses a separate presentation RNG and cannot influence simulation.
- Replays store seed, content hashes, ruleset ID, difficulty ID, and per-tick player commands.

### 13.5 Fixed simulation tick

Default: 60 ticks per second.

The application adapter may accumulate frame time and advance zero or more simulation ticks. It MUST cap catch-up work and report dropped simulation time in development builds. Rendering reads the two latest snapshots and may interpolate presentation transforms.

### 13.6 Tick order

Every simulation tick executes in this exact top-level order:

1. consume player commands for the tick;
2. decrement timers and update existing status effects;
3. compute AI commands from the pre-movement world query;
4. validate activation, continue, and respawn requests;
5. resolve facing, alignment assistance, and tank movement;
6. process normal-fire and special-fire requests;
7. spawn projectiles, fire hazards, and mines;
8. advance projectiles and continuous hazards;
9. collect collision candidates in deterministic entity-ID order;
10. resolve projectile, terrain, tank, base, and mine interactions;
11. resolve pickup collection and effects;
12. resolve deaths, score, drops, and entity removal;
13. update EnemyDirector and spawn telegraphs;
14. update objective/win/loss state;
15. emit ordered domain events;
16. produce the new immutable presentation snapshot;
17. compute optional development checksum.

Within a step, ordering rules must be documented and covered by collision tests. An agent may not reorder steps to fix a local symptom without an ADR.

### 13.7 Command model

```text
TankCommand
  actor: player(PlayerID) | ai(EntityID)
  target_tick
  move_direction: Direction | none
  normal_fire_pressed: bool
  special_fire_pressed: bool
  confirm_pressed: bool
```

Input adapters produce commands. AI produces the same movement/fire fields. The simulation validates all commands.

Local touch/controller/keyboard adapters may only emit commands for the V1 local `PlayerID`. A future network adapter will deserialize authenticated remote input into the same command value; it will not call tank methods or mutate `WorldState` directly.

### 13.8 Domain events

Required event families:

```text
PlayerActivated
PlayerEliminated
TankSpawned
TankTurned
WeaponFired
DryFire
ProjectileDestroyed
TankDamaged
TankDestroyed
MinePlaced
MineTriggered
TerrainChanged
PickupSpawned
PickupCollected
EquipmentChanged
BaseDamaged
BaseShieldChanged
EnemyWaveStarted
StageWon
StageLost
ScoreChanged
```

Events use stable IDs and primitive/value data. They do not contain SpriteKit, SwiftUI, controller, audio, or platform references.

---

## 14. Repository Structure

```text
ProjectGoldenEagle.xcodeproj
Package.swift
README.md
docs/
  PRODUCT_IMPLEMENTATION_PLAN.md
  GAME_MECHANICS_SPEC.md
  decisions/
  agent_handoffs/

Sources/
  GameCore/
    Model/                 # Pure authoritative state and project-owned values
    Rules/                 # Weapon, collision, pickup, difficulty rules
    Systems/               # Movement, combat, terrain, pickup, spawn, objective
    AI/                    # EnemyBrain and path-cost logic
    Simulation/            # Tick orchestration, RNG, snapshots, checksums

  GameApplication/
    Session/               # Game/session flow and use cases
    Replay/                # Command recording and playback
    Content/               # Content loading requirements and validation use cases

  AppleAdapters/
    Bootstrap/             # Composition root / dependency wiring
    Input/                 # Touch, GameController, keyboard adapters
    Presentation/          # SpriteKit scene, sprites, effects, full-map viewport
    Audio/                 # Domain-event-to-audio mapping
    UI/                    # SwiftUI screens and HUD
    Persistence/           # Save/settings implementation
    Platform/              # iPhone/iPad/macOS platform details

Content/
  Schemas/
  Rules/
    campaign/
  weapons/
  equipment/
  pickups/
  enemies/
  difficulties/
  stages/
  localization/

Resources/
  Art/
  Audio/
  Fonts/
  Shaders/

Tests/
  GameCoreTests/
  GameApplicationTests/
  AppleAdapterTests/
  ReplayGoldenTests/
  ContentValidationTests/
  Fixtures/

Tools/
  ContentValidator/
  StageImporter/
  ReplayInspector/
```

### 14.1 Folder ownership rules

- `Sources/GameCore/` owns rules and authoritative state and imports no Apple presentation/game framework.
- `Sources/GameApplication/` owns workflows and depends on `GameCore`.
- `Sources/AppleAdapters/` owns SwiftUI, SpriteKit, input, audio, persistence, and platform integration and depends inward.
- `Content/` owns data, not executable rules.
- `Resources/` owns presentation assets, not authoritative behavior.
- `Tools/` may import application/core code but production core code must not import tools.
- Tests may access internal state through explicit test helpers, not production debug backdoors.

### 14.2 Composition root

Only `Sources/AppleAdapters/Bootstrap/` and the application entry target wire concrete implementations together. Core systems MUST NOT instantiate UI, save, audio, scene, controller, or platform classes.

### 14.3 Swift implementation rules

- The project pins its Swift language mode and treats new compiler warnings as errors in CI after bootstrap.
- One authoritative class has one clear responsibility; avoid “manager” scripts that own unrelated systems.
- Global mutable singletons are prohibited for authoritative state. Composition happens at the app boundary.
- Core code uses explicit dependencies passed through initializers or narrow method parameters.
- Core code returns state and ordered events explicitly. `NotificationCenter`, Combine, observation, delegates, and SpriteKit callbacks MUST NOT become hidden rule-execution paths.
- Floats are prohibited for authoritative positions, cooldowns, durations, damage, and RNG decisions.
- Swift `Dictionary`/`Set` iteration order is never treated as deterministic. Keys are sorted or content is normalized into stable arrays before simulation.
- Entity processing order is explicit, normally ascending `entity_id`.
- `SKAction`, `Timer`, display callbacks, animation completion handlers, and wall-clock tasks are presentation/application tools, not simulation clocks.
- Errors in domain invariants fail loudly in development/test builds.
- Comments explain constraints and intent, not a line-by-line paraphrase of code.
- Public classes, content fields, commands, events, and migrations require short documentation.

---

## 15. Content Format and Validation

### 15.1 Canonical content

Canonical gameplay content MUST be stored as UTF-8 JSON decoded through explicit versioned `Codable` schemas or another approved reviewable text format. SpriteKit scene archives and Xcode asset catalogs MAY contain presentation-only data but are not authoritative gameplay content.

### 15.2 Stable identifiers

- IDs use lowercase snake case.
- IDs are never localized.
- Renaming a released ID requires a migration entry.
- References use IDs, never array positions or display names.

Examples:

```text
weapon: ap
equipment: shield_of_moon
enemy: ap_variant_c
pickup: base_shield
stage: frontier_01_first_defense
ruleset: campaign_v1
```

### 15.3 Validation requirements

The content validator MUST reject:

- duplicate IDs;
- missing references;
- wrong array lengths;
- unknown enum values;
- out-of-range armor, speed, power, or grid coordinates;
- negative timers/ammunition unless explicitly allowed;
- stage grid dimensions other than declared dimensions;
- enemy totals inconsistent with counts;
- spawn points inside blocking terrain;
- unreachable required base/player regions where reachability is mandated;
- missing collision matrix entries;
- missing localization keys;
- content schema version mismatches.

### 15.4 Runtime behavior

Development builds fail fast with a useful content error. Release builds show a safe fatal-content screen and log the exact failed file and field; they must not continue with partially loaded rules.

### 15.5 Canonical content hashing

- Content is normalized before hashing: UTF-8, stable field order, stable ID order, and normalized numbers.
- Replay headers store hashes of every gameplay-relevant content bundle.
- Presentation-only assets do not affect simulation hashes.
- Loading two semantically identical content sets with different source-file ordering must produce the same gameplay hash.
- Unknown fields are rejected until the schema explicitly permits forward-compatible extension data.

---

## 16. Save, Settings, and Replay

### 16.1 Save files

Separate files:

```text
settings.json
profile.json
campaign_progress.json
```

All files include `schema_version` and are written atomically. Migration functions are version-to-version and tested.

### 16.2 Campaign progress

Store:

- unlocked/completed stages;
- best difficulty completion;
- scores and optional par times;
- campaign checkpoint;
- accessibility/tutorial state;
- approved unlocks.

Do not serialize SpriteKit nodes, SwiftUI view state, textures, controller objects, or resource paths as authoritative progress.

### 16.3 Replay format

```text
ReplayHeader
  schema_version
  build_id
  ruleset_id + content_hash
  stage_id + stage_hash
  difficulty_id + difficulty_hash
  seed
  simulation_tick_rate

ReplayBody
  commands_by_tick
  optional periodic checksums
```

Replays are a testing requirement before they are a player-facing feature.

---

## 17. Performance and Platform Requirements

### 17.1 Performance targets

- Stable 60 simulation ticks per second.
- Stable 60 rendered FPS on the minimum supported iPhone target.
- No gameplay allocation spikes during routine firing or spawning after warm-up.
- Vertical-slice stress fixture: 30 tanks, 200 active projectile/hazard entities, 100 mines, and maximum terrain damage without simulation slowdown on target hardware.
- Snapshot/event queues remain bounded.
- Navigation recalculation is budgeted and measurable.

### 17.2 Renderer

SpriteKit owns 2D rendering, sprite batching, animation, particles, effects, and the orthographic full-arena presentation. SpriteKit physics MUST NOT be authoritative for movement, projectiles, terrain, mines, damage, or victory. SwiftUI owns application shell screens and may host gameplay through `SpriteView`; authoritative simulation timing remains in the application/core boundary.

### 17.3 Resolution behavior

- Arena logic never changes with device, safe area, window size, or display scale.
- Gameplay supports landscape orientation on iPhone and iPad; portrait gameplay is out of scope for V1.
- The entire universal arena is uniformly scaled to fit the available gameplay rectangle.
- No device may crop the arena, stretch one axis, or expose additional playable terrain.
- Extra aspect-ratio space is used for safe-area-aware HUD, controls, or non-gameplay background treatment; it never becomes exclusive playable terrain.
- Touch controls overlay the presentation with adjustable opacity and must automatically fade further when they overlap an active tank or critical telegraph.
- The minimum-supported-device legibility test must confirm that tanks, mines, projectiles, pickups, destructible subcells, and warning telegraphs remain distinguishable while the whole arena is visible.

M1 provisional legibility gates on the selected minimum-supported iPhone:

- a standard tank's visible footprint is at least 28×28 screen points;
- every touch action target is at least 44×44 screen points even when its visible art is smaller;
- projectile and mine silhouettes remain identifiable without relying on color alone;
- no opaque HUD element fully covers an active tank, spawn telegraph, base, pickup, or damaging hazard;
- a five-second screenshot/video review can identify the player, base, highest-threat enemy, and active special weapon effect at normal viewing distance.

If these gates fail, the team must reduce the universal grid dimensions, enlarge unit-to-cell ratios, simplify visual density, or revise UI layout. Cropping, scrolling, device-dependent playable area, and non-uniform stretching are not permitted fixes.

### 17.4 Input devices

- iPhone/iPad touch controls: floating movement control plus normal fire and special fire;
- supported Apple-platform game controllers through `GameController`;
- keyboard on iPad/macOS where available;
- exactly one active local input source controls the V1 player;
- input hot-plug and source reassignment remain outside authoritative deterministic simulation state;
- device disconnect pauses when it removes control from the only active player.

---

## 18. Testing Strategy

### 18.1 Test layers

#### Unit tests

Required for:

- fixed-point movement;
- turning/alignment;
- tank-vs-terrain collision;
- all weapon collision matrix entries;
- mine/equipment interactions;
- pickup effects and caps;
- status timers;
- AI target scoring and deterministic tie breaks;
- EnemyDirector finite counts;
- win/loss simultaneous-event rules;
- save migrations;
- content validation.

#### Simulation integration tests

Run complete headless stage fixtures with scripted inputs and assert:

- final checksum;
- event sequence;
- entity counts;
- base/player state;
- enemy counts consumed;
- absence of invalid positions.
- a test-only two-`PlayerID` fixture accepts independent tick command streams and produces stable checksums without any network or second local-input implementation.

#### Scene integration tests

Verify:

- scene bootstrap and adapter wiring;
- input-to-command mapping;
- event-to-animation/audio mapping;
- HUD reflects snapshots;
- the entire arena and all active tank nodes remain inside the gameplay viewport for every supported device-aspect fixture;
- touch controls meet minimum target size and do not create an opaque critical-information region;
- pause and restart;
- stage transitions;
- save/load behavior.

#### Replay golden tests

Each milestone records known input streams and expected periodic checksums. A gameplay-rule change must intentionally update golden data with a review note.

#### Playtests

Automated correctness cannot determine fun. Each stage and weapon requires observed playtests with:

- solo novice;
- solo experienced player;
- solo touch player on the minimum supported iPhone;
- solo controller player on iPhone/iPad;
- solo keyboard/controller player on macOS.

### 18.2 Required invariants

Checked every tick in development fixtures:

- entity IDs are unique;
- active tanks are within legal arena bounds;
- every player-owned tank references an existing stable `PlayerID`;
- armor and upgrade levels stay in range;
- ammunition stays in range;
- active-projectile counts match entities;
- enemy remaining plus alive plus spawning equals expected finite count;
- no destroyed entity remains addressable after cleanup;
- terrain masks contain only valid bits;
- event ordering is monotonic;
- simulation RNG is accessed only through named streams.

### 18.3 Continuous integration gates

Every merge must pass:

1. content schema validation;
2. Swift compilation, formatting/lint policy, and strict concurrency checks selected by M0;
3. headless unit tests;
4. simulation integration tests;
5. replay golden tests;
6. boot-to-training smoke test;
7. build-and-launch smoke test for the current primary iPhone simulator plus a real-device release configuration gate.

The initial planned commands are:

```sh
swift test
xcodebuild test -scheme ProjectGoldenEagle -destination '<pinned CI simulator destination>'
```

M0 must pin the exact scheme and simulator destination in repository documentation. One documented command or CI script must execute content validation, core tests, replay goldens, and the app smoke suite without manual Xcode interaction.

### 18.4 Definition of Done

A task is not complete merely because it runs locally. It is complete when:

- acceptance criteria pass;
- tests cover new rules and regressions;
- no unrelated files changed;
- content/schema changes are validated;
- new decisions are documented;
- debug output is removed or gated;
- public identifiers and save/replay compatibility are considered;
- another agent can understand the change from the handoff and code.

---

## 19. Milestone Plan

### M0: Planning and Repository Baseline

Deliverables:

- pinned Xcode/Swift toolchain and multiplatform Apple project bootstrap;
- repository structure;
- coding/test commands documented;
- domain/application/adapter dependency guardrails;
- content loader and validator skeleton;
- CI running an empty headless test suite;
- ADR template and agent handoff template.

Exit criteria:

- project builds without warnings or resource errors;
- non-interactive test commands succeed locally and in CI;
- forbidden domain dependencies are detected by a simple architecture check;
- invalid sample content fails with actionable errors.

### M1: Movement Lab

Deliverables:

- fixed-tick simulation kernel;
- deterministic RNG and checksums;
- universal approximately 16:9 arena bounds and terrain grid;
- one player tank;
- four-direction movement;
- collision, buffered turns, and alignment assistance;
- debug renderer and movement replay.
- fixed SpriteKit full-map presentation on the minimum supported iPhone simulator and one real iPhone.

Exit criteria:

- identical replay produces identical checksum across repeated runs;
- tank cannot enter solid terrain or leave bounds;
- corridor turning passes touch, keyboard, and controller input scripts;
- 30-minute soak test shows no positional drift.
- the full arena and player remain visible and legible with no camera movement.

### M2: Combat Lab

Deliverables:

- normal fire;
- five special weapon families;
- ammunition and cooldowns;
- brick/steel damage;
- projectile/projectile, mine, tank, and base collisions;
- weapon debug panel;
- complete collision-matrix tests.

Exit criteria:

- every listed collision category has a passing test;
- no frame-time-dependent projectile differences;
- weapon identities are distinguishable in blind control tests;
- stress fixture meets simulation target.

### M3: One-Stage Core Slice

Deliverables:

- base durability and shield;
- player death, lives, and respawn;
- EnemyBrain and EnemyDirector;
- finite composition and spawn cap;
- pickups and equipment;
- stage win/loss/restart/results;
- provisional HUD and audio;
- VS-01 playable start to finish.

Exit criteria:

- novice can understand the objective without external explanation;
- no second local player or inactive-player join UI is exposed;
- deterministic full-stage replay passes;
- stage cannot enter an unwinnable live-lock after all enemies are gone.

### M4: Three-Stage Single-Player Vertical Slice

Deliverables:

- VS-01, VS-02, VS-03;
- all weapons and equipment in representative scenarios;
- campaign difficulty profiles;
- elite/director phase;
- final replacement visual language for one theme;
- complete screen flow and checkpoint save;
- settings, accessibility baseline, controller support;
- external playtest build.

Exit criteria:

- three-stage run is complete, restartable, and save-safe;
- all design pillars are demonstrated;
- solo novice and experienced touch playtests can read and recover from at least one base crisis;
- no critical or high-severity test issue remains;
- performance and export targets pass.

### M5: Campaign Production

Deliverables:

- 12 stages and 4 themes;
- all 24 enemy archetypes;
- campaign pacing and progression;
- full audio/art replacement set;
- score and optional challenge targets;
- onboarding and localization-ready text.

Exit criteria:

- all stages pass solo completion testing on touch and at least one external controller;
- no enemy/pickup/equipment content is unused without explanation;
- difficulty curves meet playtest targets;
- campaign checkpoint migration tests pass.

### M6: Release Candidate

Deliverables:

- performance, accessibility, input, save, and export hardening;
- credits and rights audit;
- crash/error reporting strategy appropriate to distribution;
- App Store-ready iPhone packaging plus iPad and macOS build smoke coverage;
- final content hashes and replay baselines.

Exit criteria:

- zero known blocker/critical issues;
- save compatibility verified from previous public test version;
- clean install/build smoke tested on target Apple systems;
- every shipped asset has recorded provenance/rights status.

### 19.1 Requirement traceability

| Product promise | Primary implementation | First proven in | Verification |
|---|---|---|---|
| Immediate control | fixed tick, movement, input adapter | M1 | scripted turn replay + playtest |
| Destructible tactical arena | terrain masks and collision rules | M2 | quadrant-damage tests |
| Distinct weapons | weapon data and collision matrix | M2 | unit matrix + blind playtest |
| Base-defense pressure | objective, director, target scoring | M3 | full-stage replay + base-threat playtest |
| V1 single-player scope | player/session/input assignment | M3 | no second-player UI/codepath + solo completion tests |
| Equipment/terrain interaction | traversal profiles and mine rules | M3 | interaction matrix |
| Readable power and danger | snapshot/event presentation | M4 | accessibility/readability review |
| Three-stage fun loop | level content and progression | M4 | full-run playtest matrix |
| Multi-agent compatibility | dependency boundaries and task ownership | M0 onward | architecture check + scoped handoffs |
| Future two-player online readiness | stable PlayerID, deterministic commands/snapshots/replay | M1 onward | repeated cross-run checksums + two-command-stream core fixture |

---

## 20. AI-Agent Work Packages

Work packages are dependency-aware ownership units. An agent receives one package or a narrower child task.

| Package | Primary ownership | Depends on |
|---|---|---|
| WP-000 Bootstrap | project, CI, docs templates | none |
| WP-010 Simulation Kernel | `src/domain/simulation`, core models | WP-000 |
| WP-020 Content System | schemas, loader, validation | WP-000 |
| WP-030 Terrain and Movement | terrain/movement systems and tests | WP-010, WP-020 |
| WP-040 Combat | weapons/projectiles/mines/collision tests | WP-030 |
| WP-050 Player and Session | identity/lives/respawn/objectives | WP-030, WP-040 |
| WP-060 Pickups and Equipment | pickup/effect systems | WP-040, WP-050 |
| WP-070 AI and Director | AI queries, brains, navigation, spawns | WP-030, WP-040 |
| WP-080 Presentation | snapshots to SpriteKit sprites/effects/full-map viewport/audio | WP-010, event contracts |
| WP-090 UI and Persistence | screens, HUD, settings, save | WP-050, WP-080 |
| WP-100 Level Content | stages, waves, tutorial, balance | WP-020, WP-060, WP-070 |
| WP-110 QA and Replay | test harness, goldens, stress fixtures | all relevant packages |

### 20.1 Parallel-work rule

Agents MAY work in parallel only when their owned paths and public contracts do not overlap. Contract changes must be coordinated before adapter/content work that consumes them.

### 20.2 Agent task input template

Every coding-agent prompt SHOULD specify:

```text
Task ID:
Objective:
Milestone:
Owned files/directories:
Files allowed to read:
Files prohibited from editing:
Upstream contracts:
Required behavior:
Acceptance criteria:
Required tests:
Out of scope:
Known risks/assumptions:
Expected handoff artifacts:
```

### 20.3 Agent handoff template

Every agent response or `docs/agent_handoffs/` entry SHOULD include:

```text
Task ID and outcome
Changed files
Behavior implemented
Tests added and exact results
Content/schema changes
Decisions or assumptions
Known limitations
Follow-up tasks
Compatibility/migration notes
```

### 20.4 Rules for all implementation agents

1. Read this document and relevant companion sections before editing.
2. Inspect existing code and tests; do not assume the repository matches the prompt.
3. Preserve user or other-agent changes outside owned scope.
4. Do not put gameplay logic into scenes, animation callbacks, HUD, or audio.
5. Do not add a global interface/ports package.
6. Do not use variable frame delta for authoritative simulation.
7. Do not call nondeterministic random APIs inside domain logic.
8. Do not change stable content IDs casually.
9. Add or update tests with every gameplay-rule change.
10. Report uncertainty; do not conceal it with guessed original behavior.
11. Prefer the smallest coherent change that satisfies the assigned acceptance criteria.
12. Do not implement networking, local multiplayer, procedural generation, or meta progression without an accepted decision. iPhone touch support is required V1 scope, not an expansion.

---

## 21. Initial Task Backlog

### Foundation

- GE-001 Create the Xcode multiplatform project, Swift packages/targets, and folder structure.
- GE-002 Add non-interactive Swift/Xcode test runners and CI commands.
- GE-003 Add architecture dependency check.
- GE-004 Add ADR and agent handoff templates.
- GE-005 Implement structured logging with development/release levels.

### Content

- GE-020 Define JSON schemas and stable ID registry.
- GE-021 Implement content loader and aggregated validation errors.
- GE-022 Encode campaign v0.1 weapon definitions.
- GE-023 Encode reference-derived enemy table and modern campaign overrides.
- GE-024 Encode equipment and pickup definitions.
- GE-025 Implement stage JSON and validation fixture.

### Simulation

- GE-040 Implement entity IDs, world state, fixed tick, snapshots, and checksum.
- GE-041 Implement named deterministic RNG streams.
- GE-042 Implement terrain grid and quadrant masks.
- GE-043 Implement cardinal movement, collision, and speed accumulator.
- GE-044 Implement turn buffer and alignment assistance.
- GE-045 Implement command ingestion and replay recording.

### Combat

- GE-060 Implement weapon cooldown/ammunition state.
- GE-061 Implement projectile advancement and collision candidate collection.
- GE-062 Implement terrain damage.
- GE-063 Implement tank/base damage and destruction.
- GE-064 Implement Rapid, Fire, AP, Explosion, and Mine behavior.
- GE-065 Implement collision matrix validator and tests.

### Game loop

- GE-080 Implement stable PlayerID, V1 player activation, death, lives, respawn, and elimination.
- GE-081 Implement base shield and objective system.
- GE-082 Implement pickup spawning, grace period, collection, and effects.
- GE-083 Implement equipment traversal/mine interactions.
- GE-084 Implement EnemyDirector finite composition and spawn telegraphs.
- GE-085 Implement EnemyBrain baseline movement, target, and fire decisions.
- GE-086 Implement navigation profiles and terrain invalidation.

### Presentation and UX

- GE-100 Implement the universal 48×27 provisional arena and uniform full-map viewport in SpriteKit.
- GE-101 Implement snapshot-driven SpriteKit tank/projectile/terrain presentation.
- GE-102 Implement event-driven effects and audio.
- GE-103 Implement the single-player responsive SwiftUI/SpriteKit HUD with no empty player-2 panel.
- GE-104 Implement title-to-results flow.
- GE-105 Implement touch layout customization, supported controller assignment/remapping, keyboard input, and accessibility settings.
- GE-106 Implement checkpoint persistence and migration test.

### Content production and validation

- GE-120 Build VS-01.
- GE-121 Build VS-02.
- GE-122 Build VS-03.
- GE-123 Run the solo touch/controller/device playtest matrix and record findings.
- GE-124 Tune movement and weapon v0.1 values.
- GE-125 Lock vertical-slice replay goldens.

---

## 22. Balance and Playtest Framework

### 22.1 Metrics to record

No network telemetry is required for internal tests. A local playtest report SHOULD record:

- completion/failure and reason;
- stage duration;
- base durability over time;
- player deaths and respawns;
- damage by weapon;
- ammunition gained, spent, and wasted at cap;
- pickup collection/replacement choices;
- enemy leakage to base;
- time with no valid enemy engagement;
- dominant weapon/equipment combination;
- control-error notes such as failed turns or wall snagging.

### 22.2 Fun-quality questions

After each playtest ask:

1. Was the immediate objective obvious?
2. Did movement failures feel like player error or control friction?
3. Could players identify the dangerous enemy before taking damage?
4. Did the base create exciting pressure or merely frustration?
5. Could the solo player read and prioritize simultaneous threats without camera management?
6. Did a pickup create an interesting decision?
7. Was any weapon always the correct answer?
8. Did any stage contain dead time or an unfair collapse?
9. Would the player choose to replay with a different weapon/equipment plan?

### 22.3 Balance-change discipline

- Change one causal group at a time where practical.
- Record before/after values and intended outcome.
- Do not update replay goldens until behavior change is accepted.
- Separate bug fixes from balance changes.
- Treat “more enemies” as a last resort, not the default difficulty tool.

---

## 23. Risks and Mitigations

| Risk | Consequence | Mitigation |
|---|---|---|
| Exact reference behavior remains uncertain | Endless reverse-engineering delays | Modern campaign design is authoritative; reference unknowns remain data-driven |
| Too much content before feel is proven | Expensive rework | Three-stage vertical slice before 12-stage production |
| Rules leak into SpriteKit scenes or SwiftUI views | Fragile tests and incompatible agent work | Strict inward dependencies, snapshots/events, architecture checks |
| Determinism is postponed | Replays/networking/testing become expensive | Fixed tick, integer state, named RNG from M1 |
| Future online mode requires a core rewrite | Networking becomes prohibitively expensive | Stable PlayerID, tick commands, snapshots, checksums, and a two-command-stream core-only fixture from M1; no networking in V1 |
| Weapons differ only cosmetically | Shallow decision-making | Explicit role contract and collision matrix per weapon |
| Base failure feels unfair | Player frustration | Modern durability, shield, readable attack cues, authored threat routes |
| AI becomes omniscient | Unfair difficulty | World query limits, reaction intervals, telegraphs, no future-input access |
| Canonical data becomes inconsistent | Runtime bugs across agents | Text schemas, fail-fast validator, stable IDs |
| Original assets create distribution risk | Release blockage | Replacement assets and provenance ledger from the start |
| Scope expands to online or non-Apple ports too early | Vertical slice never stabilizes | Explicit deferred scope and adapter extension points |
| Other AI models recommend conflicting redesigns | Planning churn | Review feedback must cite requirement IDs and propose ADRs |

---

## 24. Open Questions That Do Not Block M0–M2

These are intentionally open and must not be guessed into fixed product rules prematurely:

1. Final commercial title and visual identity.
2. Exact campaign base durability and repair availability.
3. Exact movement base speed and turn-assistance window.
4. Exact weapon per-level damage/cooldown arrays.
5. Whether a limited continue option exists after the V1 player exhausts all lives.
6. Final score economy and extra-life thresholds.
7. Whether weapon-switch pickups retain all previous ammunition or a reduced amount.
8. Exact pacing, ordering, and optional branching among the fixed twelve campaign stages.
9. Final minimum supported iPhone model after the M1 full-map legibility and stress tests.
10. Whether foliage blocks AI perception, only presentation, or both in selected stages.

Each question has a safe interface/data boundary in the architecture. None justifies delaying simulation, movement, combat, or the one-stage slice.

---

## 25. External Review Instructions

Reviewers should not merely propose unrelated features. They should test whether this plan is internally coherent and implementable.

### 25.1 Required review categories

1. Product clarity and preservation of the intended core.
2. Scope realism and milestone dependency order.
3. Swift/SpriteKit/SwiftUI technical feasibility and Apple-platform lifecycle risks.
4. Domain/application/adapter dependency correctness.
5. Determinism and future online-readiness.
6. Data contracts and migration safety.
7. Missing gameplay edge cases.
8. AI fairness and navigation feasibility.
9. Test completeness and measurable acceptance criteria.
10. Co-op, accessibility, and UX risks.
11. IP/asset provenance risks.
12. Contradictions, ambiguous terms, and unowned decisions.

### 25.2 Severity definitions

| Severity | Meaning |
|---|---|
| Blocker | Implementation cannot proceed coherently or would require major redesign |
| High | Likely to cause substantial rework, incorrect gameplay, or failed milestone |
| Medium | Important ambiguity, test gap, or maintainability issue |
| Low | Refinement, clarity, or optional improvement |

### 25.3 Review finding format

```text
Finding ID:
Severity:
Referenced section/requirement:
Problem:
Why it matters:
Concrete proposed change:
Tradeoffs:
Does it require an ADR? yes/no
```

### 25.4 Review acceptance rule

Feedback is accepted when it:

- identifies a concrete contradiction, omission, feasibility issue, or measurable improvement;
- cites the affected section or decision ID;
- respects the product pillars and current milestone scope;
- gives a change that can be implemented or documented;
- acknowledges tradeoffs.

“Use another engine,” “add online now,” “add local multiplayer,” “make it a roguelike,” or “copy the original exactly” are out-of-scope redesigns unless supported by new product direction.

---

## 26. Implementation Readiness Checklist

Before the first coding task starts, confirm:

- [ ] Exact Xcode version, Swift language mode, schemes, and deployment targets are selected and recorded.
- [ ] Repository and license/provenance policy exist.
- [ ] This document and reference documents are under version control.
- [ ] M0 task ownership is assigned.
- [ ] Headless test command is agreed.
- [ ] Canonical content format is accepted.
- [ ] The single campaign ruleset ID and schema version are reserved.
- [ ] Placeholder assets are original or safely licensed.
- [ ] The Soft Modern Mechanical Toy Arcade art direction and v2 styleboards are referenced by the asset pipeline.
- [ ] The enumeration-only asset list and provenance fields are accepted.
- [ ] iPhone signing, simulator, and at least one real-device development path are available.
- [ ] First movement replay fixture is defined.

Before M4 vertical-slice review, confirm:

- [ ] Three stages are playable end to end in single-player.
- [ ] All five special weapons and four equipment types have test coverage.
- [ ] Every required collision pair is defined.
- [ ] Content validation passes with no warnings.
- [ ] Full-run deterministic replay passes.
- [ ] Checkpoint save/load and migration tests pass.
- [ ] Touch controls and at least one supported external controller have been tested on iPhone; iPad/macOS input smoke tests pass.
- [ ] Accessibility baseline is present.
- [ ] Stress target passes on primary hardware.
- [ ] External reviewer blocker/high findings are resolved or explicitly accepted.

---

## 27. Final Planning Statement

The project has enough reference information to build its distinctive systems without waiting for a clean original executable. Reference research should now serve three purposes only:

1. preserve the original game’s unusual design ideas;
2. seed content and tuning values;
3. provide non-shipping comparison fixtures for selected reference-derived mechanics.

The critical delivery path is:

```text
Architecture baseline
  -> deterministic movement
  -> complete combat matrix
  -> one-stage game loop
  -> three-stage single-player vertical slice
  -> twelve-stage campaign production
  -> release hardening
```

The plan succeeds if multiple agents can implement separate packages, combine them without hidden presentation dependencies, and prove behavior through content validation, simulation tests, and replay checks—while playtests, rather than nostalgia alone, decide whether the modern campaign is genuinely fun.
