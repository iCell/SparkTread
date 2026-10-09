# Project Golden Eagle

## Product, Game Design, and Implementation Plan

Document version: 2.3  
Status: Planning baseline for implementation and external AI review  
Date: 2026-09-01  
Primary stack: Swift + SpriteKit + SwiftUI in the current stable Xcode toolchain  
Primary target: iPhone, landscape orientation  
Secondary targets: iPad, then macOS (V1 ships for iPhone only — ADR-0028)  
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

1. `GAME_RULES.md` (R5) for every gameplay rule (ADR-0018);
2. this document and accepted Architecture Decision Records for architecture, process, formats, and platform;
3. `STAGE_52_METADATA.csv` for recovered candidate reference-stage metadata;
4. automated tests and checked-in content schemas;
5. issue descriptions, agent prompts, comments, and informal notes.

Reference-game research does not override `GAME_RULES.md` or an explicit modern-product decision in this document.

### 1.4 Required companion material

- `DOCUMENT_INDEX.md`: reading order, authority order, and current fixed-direction index.
- `GAME_RULES.md`: the single gameplay rulebook (R5, 2026-09-15).
- `STAGE_52_METADATA.csv`: 52 candidate reference-stage metadata records.
- `ASSET_PRODUCTION_MANIFEST.md`: complete visual/audio inventory, art direction, production method, and provenance requirements.
- `ASSET_REQUIREMENTS_LIST_ZH.md`: enumeration-only Chinese checklist of every required shipping asset family; it does not authorize generation.

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

Version 2.1 locks the approved visual direction as **Soft Modern Mechanical Toy Arcade** and adds a consolidated Chinese master summary plus an enumeration-only asset checklist (the master summary was retired on 2026-09-15; GAME_RULES.md and this plan are the surviving pair). It does not authorize or perform bulk asset generation.

### 1.8 Version 2.2 change record

Version 2.2 applies the accepted external design/engineering review (findings F-01–F-28) without changing product direction:

- one spatial unit system: `1024` subunits per cell and `512`-subunit destruction quadrants (ADR-0001);
- one external input contract, `PlayerCommand`, with a versioned `session_request` enum; AI intents are internal-only; turn buffering and alignment assistance are core-owned, serialized state (ADR-0002);
- serializable value-type world state, mid-stage suspend/resume, required development/test checksums, and a resimulation throughput target (ADR-0003);
- edge-to-edge arena rendering, a pinned 390-point-class minimum-device floor, and gutter-first touch layout rules (ADR-0004);
- swept collision, a per-tick displacement cap, completed collision categories, chain-detonation ordering, and penetration/durability semantics;
- mine launch/flight and ice-slide contracts; drop-table and authored base-repair contracts; reachability, spawn-blocked, and respawn-blocked rules;
- campaign-spanning replay headers; Apple platform lifecycle requirements; raw multi-touch input requirement; terrain chunk-rendering rule;
- `ArenaSpecification` extraction, ID-canon corrections (`freeze_enemy`, `ammo_crate`, `ap_c`), work-package path fixes, closure of the ammunition-retention question, and the new A0 style-lock milestone.

### 1.10 Version 2.4 change record

Version 2.4 applies ADR-0018: `GAME_RULES.md` R5 becomes the single gameplay authority. Sections 6–10 of this plan are reduced to an index into it, and gameplay statements elsewhere in this plan (including milestone, backlog, and risk text written earlier) yield to R5 where they conflict. V1 ships five weapon families (normal, rapid, fire, AP, explosion), two equipment items (AmphiTank, AntiSkid), twenty enemy types, and twenty-two pickups; the Mine weapon, mine-family enemies, Shield of Moon, and Memory of Sea are removed.

### 1.9 Version 2.3 change record

Version 2.3 records one owner gameplay decision (ADR-0005): allied damage to the player's own base becomes difficulty-scoped ruleset data (`allied_base_damage`) — disabled on Casual, enabled on Standard and Veteran with a clearly telegraphed own-fire cue. Future co-op player-versus-player damage remains disabled.

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
- meaningful rapid, fire, armor-piercing, and explosion interactions;
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
- 4 special weapon families;
- 2 equipment families;
- all 20 enemy archetypes (GAME_RULES §9.1), with modern campaign tuning;
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
- normal fire plus all 4 special weapon families;
- both equipment families;
- at least 5 enemy archetypes, one from each weapon family;
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
| D-003 | All shipping stages use one universal fixed-size arena. Dimensions pinned at 56×27 base terrain cells by ADR-0009 (the one-shot M1 tuning this row authorized; originally a provisional 48×27 at ~16:9). | Fixed |
| D-004 | Gameplay is 2D top-down. The complete arena and every active tank remain visible at all times; there is no camera follow, scrolling, gameplay zoom, or split-screen. | Fixed |
| D-005 | Simulation runs at a fixed 60 Hz tick using integer or fixed-point state. Rendering may interpolate. | Fixed |
| D-006 | Core input is four-direction movement, normal fire, and special fire. | Fixed |
| D-007 | V1 ships as single-player only. Local multiplayer, split-screen, and networking are not implemented in V1. | Fixed |
| D-008 | Authoritative state and commands use stable `PlayerID` values and support a future capacity of two players; V1 creates only one player. | Fixed |
| D-009 | The modern ruleset is authoritative and may intentionally improve on the reference game. Reference behavior is research evidence, not a second shipping mode. | Fixed |
| D-010 | Allied damage to the player's own base is difficulty-scoped ruleset data (`allied_base_damage`): disabled on Casual; enabled on Standard and Veteran with a clearly telegraphed own-fire hit cue (ADR-0005). Allied damage to allied tanks, including the future co-op partner, remains disabled. | Fixed |
| D-011 | The first campaign contains 12 handcrafted stages; the vertical slice contains 3. | Fixed |
| D-012 | Gameplay rules MUST NOT be implemented inside HUD, animation, audio, or scene scripts. | Fixed |
| D-013 | Content is canonical in reviewable text files and validated before play. | Fixed |
| D-014 | Agents MUST preserve determinism and must not use frame-rate-dependent gameplay logic. | Fixed |
| D-015 | No original binary or extracted asset may be committed to the distributable game without confirmed rights. | Fixed |
| D-016 | Device adaptation uses uniform scaling and safe-area-aware UI; device aspect ratio MUST NOT reveal or hide playable terrain. The gameplay arena MAY render edge-to-edge beneath system UI overlays; HUD and interactive controls respect safe areas (ADR-0004). (ADR-0018 §3 briefly confined the arena to the safe rectangle; ADR-0022 / GAME_RULES R5.9 §15.1 restored the full-screen fit with a decorative white-steel bezel over the gutter — cutouts may cover the bezel, never the base, spawns or HUD-critical info) | Fixed |
| D-017 | SpriteKit and SwiftUI are presentation/platform adapters. Authoritative rules live in a pure Swift `GameCore` module and MUST NOT import SpriteKit, SwiftUI, GameKit, AVFoundation, Foundation, or platform UI APIs. | Fixed |
| D-018 | Future online play consumes the same tick-addressed command API as local input. V1 implements replay/determinism foundations but no speculative networking layer or unused transport interface. V1 obligations additionally include a fully serializable value-type `WorldState` (including RNG stream positions and buffered input state), a serialize→restore→resume checksum test from M1 onward, and a headless resimulation throughput target (ADR-0003). | Fixed |
| D-019 | Shipping art uses the approved Soft Modern Mechanical Toy Arcade direction: moderately rounded silhouettes, large color panels, satin enamel and soft molded-plastic accents, restrained mechanical detail, strict top-down readability, and no faces/eyes or preschool styling. | Fixed |
| D-020 | The soft v2 arena and tank-family styleboards are visual references, not shipping sprite sheets. Production assets require separate extraction/redraw, technical normalization, readability review, and provenance approval. | Fixed |

The repository MUST record the exact Xcode and Swift toolchain used for release builds. Toolchain upgrades require the complete automated regression suite and an ADR when they change build settings, language mode, serialization, timing, or runtime behavior.

---

## 5. Game Modes and Rulesets

### 5.1 Campaign

This is the default product experience.

- Three difficulty presets: Casual, Standard, Veteran.
- Base has visible durability instead of universal one-hit failure.
- Allied fire never damages allied tanks. Whether the player's own fire damages the base is difficulty data: the base is immune on Casual and vulnerable on Standard and Veteran, with clear own-fire cues (ADR-0005).
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
- testing terrain and weapon interactions;
- recording deterministic input replays.

### 5.3 Future Two-Player Online Co-op

Two-player online co-op is DEFERRED until the V1 campaign is stable. It will:

- use the same fixed arena and full-map camera;
- support exactly two active player-controlled tanks;
- send tick-addressed `PlayerCommand` values into the same `GameCore` command boundary;
- use stable `PlayerID` ownership for tanks, pickups, score, respawn, and results;
- scale enemy composition and pacing through mode data rather than branching combat code;
- choose matchmaking, transport, authority, prediction, rollback, reconnect, and host-migration policies in a dedicated pre-network ADR.

V1 MUST NOT ship dormant sockets, matchmaking code, a generic `NetworkManager`, or an unused network abstraction. The V1 obligation is deterministic command simulation, snapshots, required development checksums, multi-player-capable data identifiers, and a fully serializable, cheaply copyable authoritative state that supports faster-than-real-time resimulation (ADR-0003).

### 5.4 Future Challenge Mode

Challenge mode is DEFERRED until the campaign loop is stable. It may reuse campaign stages with fixed loadouts, mutators, time targets, or seeded enemy waves.

---

## 6–10. Gameplay Rules (moved to `GAME_RULES.md`)

The gameplay specification that used to live in sections 6–10 is superseded by `GAME_RULES.md` R5 (ADR-0018). Code comments and older records that cite these section numbers resolve through this table.

| Former plan section | `GAME_RULES.md` R5 |
|---|---|
| §6.1 Coordinate system, §6.2 Direction convention | §2.2 |
| §6.3 Player controls | §4.2, §5.1 |
| §6.4 Player state | §2.1, §11.3 |
| §6.5 Player death and re-entry | §11.3 |
| §6.6 Base rules | §11.1, §11.2 |
| §6.7 Win and loss | §11.4 |
| §6.8 Stage pacing | §9.3 |
| §7.1 Movement model, §7.2 Speed levels | §4.1, §4.2 |
| §7.3 Terrain types | §2.3, §3.1 |
| §7.4 Destructible terrain | §3.2–§3.4, §6.4 |
| §7.5 Equipment traversal | §4.3, §4.4, §8 |
| §8.1 Fire channels | §5.1 |
| §8.2 Weapon families, §8.3 Ammunition, §8.4 Weapon data | §5.2, §5.3 |
| §8.5 Collision categories | §6, §12 |
| §8.6 Mines and equipment | removed by ADR-0018 |
| §8.7 Fire team filtering | §7.3 |
| §9.1 Equipment slot | §8 |
| §9.2 Upgrade axes | §10.1, §11.3 |
| §9.3 Pickup behavior, §9.4 Required pickups | §10 |
| §10.1 Enemy content model | §9.1 |
| §10.2–§10.5 AI architecture, states, navigation, targeting | §9.2 |
| §10.6 Readability and fairness | §1, §9.1 |
| §10.7 Campaign difficulty profiles | §9.2 |

---

## 11. Level and Campaign Design

### 11.1 Stage data

```text
StageDefinition
  schema_version: int
  id: string
  display_name_key: string
  theme_id: string
  arena_spec_id: string  # references the single universal ArenaSpecification content file
  terrain_layers: array
  base_spawn: GridPos
  player_spawns_by_id: map<PlayerID, GridPos> # V1 activates only player 1
  enemy_spawns: array<SpawnPoint>
  enemy_counts: map<enemy_archetype_id, int>
  max_alive_enemies: int
  initial_enemy_delay_ticks: int
  pickup_spawns: array
  hidden_pickups: array  # 2×2 area; revealed when all 16 quadrants hold no wall (GAME_RULES §10.2)
  fort_template: array   # explicit Flag On Guard wall cells; empty = no temporary walls (GAME_RULES §11.2)
  drop_table_id: string | null
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
- Hidden pickups should be learnable through visual language, not arbitrary pixel hunting; a hidden pickup is revealed when its 2×2 area holds no wall quadrant (GAME_RULES §10.2).
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
- Fire enemies.
- Two simultaneous threats create a readable solo prioritization decision with a recoverable response window.
- Target duration: 8 minutes.

#### VS-03: Eagle Under Siege

Purpose: validate the full combat system and crisis recovery.

- AP and Explosion enemies.
- Elite wave with a protected terrain breaker.
- Base shield/repair opportunity before final pressure.
- Multiple destructible approaches.
- Target duration: 10 minutes.

### 11.4 Twelve-stage campaign structure

The twelve-stage content budget, themes (sand, forest, water, snow/ice), enemy totals, alive caps, and required mechanics per stage are defined in `GAME_RULES.md` §14.1–§14.2.

Stage 12 should be a multi-phase encounter implemented using ordinary simulation rules plus authored director phases, not a separate incompatible boss engine.

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

The required HUD contents and control layout are defined in `GAME_RULES.md` §15.2.

The HUD layout must be data-driven by player count. V1 renders one player panel with no empty player-2 placeholder; future online co-op may render a second compact panel without changing `GameCore` snapshots.

### 12.3 Readability rules

- Team identity must not rely on color alone.
- Invulnerability, base shield, freeze, and equipment must have unique silhouettes or effects.
- HUD text must remain readable at the minimum supported window size.
- Screen shake, flashes, and particles must have intensity options.
- Destructive terrain state must match collision state on the same rendered frame after event consumption.

### 12.4 Audio rules

- Normal and four special weapons have distinguishable attack sounds.
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
- color-blind-safe team cues;
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

- `SpriteKit`, `SwiftUI`, `GameKit`, `GameController`, `AVFoundation`, `Foundation`, or UIKit/AppKit view types;
- `SKScene`, `SKNode`, `SKPhysicsWorld`, `SpriteView`, or texture/asset identifiers;
- filesystem APIs;
- window/display APIs;
- wall-clock time;
- nondeterministic global random calls.

`GameCore` MUST NOT import Foundation; it uses the Swift standard library only (`Codable`, integers, arrays, and dictionaries are standard-library features). A specific Foundation type may be admitted only by name in the architecture-check allowlist with a documented determinism note. Authoritative vectors, timers, and IDs must be project-owned value types.

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
- projectiles, fire patches, pickups, terrain layers and masks;
- enemy composition and spawn timers;
- base state;
- RNG state;
- stage objective state;
- turn-buffer, alignment-assist, and slide state.

Authoritative simulation state is a value type and fully `Codable`, including RNG stream positions, buffered input, and deferred effects (ADR-0003).

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

The authoritative per-tick order is `GAME_RULES.md` §12 (input and timers → intents and respawns → movement → firing → the single time-ordered contact queue with immediate explosions → fire → deaths → pickups → spawning and win/loss). The implementation additionally emits ordered domain events, exposes the value-type world as the presentation snapshot, and computes the periodic state checksum (required in development, test, and golden-replay configurations; optional in release).

Within a step, ordering rules must be documented and covered by collision tests. An agent may not reorder steps to fix a local symptom without updating `GAME_RULES.md` through an ADR.

### 13.7 Command model

```text
PlayerCommand  # the only external input contract (ADR-0002)
  player_id: PlayerID
  target_tick: int
  move_direction: Direction | none
  normal_fire_pressed: bool
  special_fire_pressed: bool
  session_request: none | confirm | continue | activation  # versioned enum

TankIntent  # internal-only AI output; same movement/fire fields, never ingested externally
  entity_id: int
  move_direction: Direction | none
  normal_fire_pressed: bool
  special_fire_pressed: bool
```

Input adapters produce `PlayerCommand` values. AI brains emit `TankIntent` values deterministically inside the simulation; they are never transmitted, recorded as external input, or accepted by the ingestion API. A tick with no command for a player resolves to neutral input (no movement, no fire, no request). The simulation validates all commands.

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
SparkTread.xcodeproj
Package.swift
project.yml
README.md
GAME_RULES.md
PRODUCT_IMPLEMENTATION_PLAN.md
docs/
  CURRENT_REVIEW.md
  decisions/
  agent_handoffs/
  pixel/

Sources/
  GameCore/
    Model/                 # Pure authoritative state and project-owned values
    Rules/                 # Weapon, collision, pickup, difficulty rules
    Simulation/            # Tick orchestration, RNG, snapshots, checksums

  GameApplication/
    Session/               # Game/session flow and use cases
    Replay/                # Command recording and playback
    Content/               # Content loading requirements and validation use cases
    Persistence/           # Save documents and migration

  AppleAdapters/
    Bootstrap/             # Composition root / dependency wiring
    Input/                 # Touch, GameController, keyboard adapters
    Presentation/          # SpriteKit scene, sprites, effects, audio mapping, full-map viewport
    UI/                    # SwiftUI screens and HUD
    Persistence/           # Save/settings implementation
    Resources/             # Bundled audio and adapter-owned resources

  GoldenEagleApp/          # iOS app entry point, Info.plist, asset catalog

Content/
  Schemas/
  campaigns/
  difficulties/
  stages/

Vendor/
  SparkTreadPixel/         # Pixel-art submodule: .atlas folders and Metadata/

Tests/
  GameCoreTests/
  GameApplicationTests/
  AppleAdapterTests/
  ContentValidationTests/

Scripts/

Tools/
  ContentValidator/
  reference_measure/
```

### 14.1 Folder ownership rules

- `Sources/GameCore/` owns rules and authoritative state and imports no Apple presentation/game framework.
- `Sources/GameApplication/` owns workflows and depends on `GameCore`.
- `Sources/AppleAdapters/` owns SwiftUI, SpriteKit, input, audio, persistence, and platform integration and depends inward.
- `Content/` owns data, not executable rules.
- `Sources/AppleAdapters/Resources/` owns presentation assets, not authoritative behavior.
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

The universal arena dimensions live in a single `ArenaSpecification` content file referenced by ruleset ID; stage files do not carry their own copies.

### 15.2 Stable identifiers

- IDs use lowercase snake case.
- IDs are never localized.
- Renaming a released ID requires a migration entry.
- References use IDs, never array positions or display names.

Examples:

```text
weapon: ap
equipment: amphi_tank
enemy: ap_c
pickup: base_shield
stage: frontier_01_first_defense
ruleset: campaign_v1
```

The stable-ID registry created by GE-020 (`Content/Schemas/id_registry`) is the single canonical source for every ID; documents, content, and asset filenames conform to it.

### 15.3 Validation requirements

The content validator MUST reject:

- duplicate IDs;
- missing references;
- wrong array lengths;
- unknown enum values;
- armor, speed, power, or grid coordinates outside the per-entity-class legal ranges declared in the schema (player speed `0..3`; enemy speed levels may be negative within the declared enemy range);
- negative timers/ammunition unless explicitly allowed;
- terrain layers inconsistent with the referenced `ArenaSpecification`;
- enemy totals inconsistent with counts;
- spawn points inside blocking terrain;
- unreachable required base/player regions where reachability is mandated;
- an enemy archetype in `enemy_counts` whose assigned spawns cannot reach the base region under that archetype's traversal profile on the undamaged map (a per-stage waiver flag with written justification is permitted);
- drop-table references to unknown pickups, or a missing `drop_table_id` while any listed enemy declares a `drop_class`;
- weapon data whose per-tick displacement can exceed one cell (`1023` subunits per tick);
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
suspended_session.json
```

All files include `schema_version` and are written atomically. Migration functions are version-to-version and tested.

`suspended_session.json` stores a mid-stage authoritative `WorldState` snapshot plus the command log to date, written when the app leaves the foreground mid-stage (§17.5); it is validated on load and deleted on stage completion or abandonment.

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
  initial_session_state  # versioned + hashed: per-player carried upgrades/ammo/lives and campaign checkpoint hash

ReplayBody
  commands_by_tick
  periodic checksums  # required for golden replays and dev/test recordings; optional in release recordings
```

Replays are a testing requirement before they are a player-facing feature.

A campaign replay is an ordered list of stage replays; the replay harness verifies that each stage's exit state equals the next stage's `initial_session_state`.

---

## 17. Performance and Platform Requirements

### 17.1 Performance targets

- Stable 60 simulation ticks per second.
- Stable 60 rendered FPS on the minimum supported iPhone target.
- No gameplay allocation spikes during routine firing or spawning after warm-up.
- Vertical-slice stress fixture: 30 tanks, 200 active projectile/hazard entities, and maximum terrain damage without simulation slowdown on target hardware.
- Snapshot/event queues remain bounded.
- Navigation recalculation is budgeted and measurable.
- Headless resimulation runs at 10× real time or faster on the minimum supported device (rollback/resync feasibility evidence; ADR-0003).

### 17.2 Renderer

SpriteKit owns 2D rendering, sprite batching, animation, particles, effects, and the orthographic full-arena presentation. SpriteKit physics MUST NOT be authoritative for movement, projectiles, terrain, fire, damage, or victory. SwiftUI owns application shell screens and may host gameplay through `SpriteView`; authoritative simulation timing remains in the application/core boundary.

Destructible terrain rendering uses composited chunk textures (for example 6×6-cell chunks) regenerated from `TerrainChanged` events; a one-node-per-quadrant scene graph is prohibited at arena scale.

### 17.3 Resolution behavior

- Arena logic never changes with device, safe area, window size, or display scale.
- Gameplay supports landscape orientation on iPhone and iPad; portrait gameplay is out of scope for V1. (V1 ships for iPhone only; iPad runs it in iPhone compatibility mode — ADR-0028.)
- The entire universal arena is uniformly scaled to fit the available gameplay rectangle.
- No device may crop the arena, stretch one axis, or expose additional playable terrain.
- Extra aspect-ratio space is used for safe-area-aware HUD, controls, or non-gameplay background treatment; it never becomes exclusive playable terrain.
- Touch controls overlay the presentation with adjustable opacity and must automatically fade further when they overlap an active tank.
- The minimum-supported-device legibility test must confirm that tanks, projectiles, fire, pickups, and destructible subcells remain distinguishable while the whole arena is visible.

Fixed rendering policy (ADR-0004 as amended by ADR-0018): decorative background may fill the screen, but the playable map and its base, spawn points, and projectiles stay inside the system safe rectangle (`GAME_RULES.md` §15.1); HUD and interactive controls remain safe-area-aware; bottom-edge system gestures are deferred during gameplay. The pinned minimum-supported-device floor is the 390×844-point class; 375-point-height devices (iPhone SE, mini) are below the floor, which may widen only through a new ADR.

M1 provisional legibility gates on the pinned floor device:

- a standard tank's visible footprint is at least 18 screen points wide (revised by ADR-0006 to the accepted PixelProduction scale, ~19–20×15 points; originally 28×28);
- every touch action target is at least 44×44 screen points even when its visible art is smaller;
- projectile silhouettes remain identifiable without relying on color alone;
- no opaque HUD element fully covers an active tank, spawn point, base, pickup, or damaging hazard;
- a five-second screenshot/video review can identify the player, base, highest-threat enemy, and active special weapon effect at normal viewing distance;
- the default touch layout keeps thumb contact zones in the horizontal gutters where the device aspect provides them, and a thumb-zone occlusion review passes on the floor device.

If these gates fail, the team must reduce the universal grid dimensions, enlarge unit-to-cell ratios, simplify visual density, or revise UI layout. Cropping, scrolling, device-dependent playable area, and non-uniform stretching are not permitted fixes.

### 17.4 Input devices

- iPhone/iPad touch controls: floating movement control plus normal fire and special fire;
- gameplay touch input is captured as raw multi-touch events through a UIKit/AppKit hosting view owned by the input adapter; SwiftUI gesture recognizers are limited to menus and HUD;
- the default touch layout anchors controls in the horizontal gutters produced by uniform arena fit on taller-than-16:9 devices and overlays the arena only where the device is approximately 16:9;
- supported Apple-platform game controllers through `GameController`;
- keyboard on iPad/macOS where available;
- exactly one active local input source controls the V1 player;
- input hot-plug and source reassignment remain outside authoritative deterministic simulation state;
- device disconnect pauses when it removes control from the only active player.

### 17.5 Platform lifecycle

- Losing foreground/active status pauses gameplay immediately and, when mid-stage, writes `suspended_session.json` before suspension.
- Cold launch after a mid-stage termination offers deterministic resume from the suspended snapshot; declining discards it.
- Audio-session interruptions (calls, Siri, route changes) pause gameplay and restore cleanly.
- Bottom-edge system gestures are deferred during gameplay; the home indicator uses its dimmed/auto-hide behavior.
- The simulation clock driver is a display-link-driven accumulator owned by the application adapter, pinned by an M0/M1 decision record; SpriteKit's automatic view pausing MUST NOT become an undocumented second clock authority.
- The fixed 60 Hz simulation is unaffected by 120 Hz ProMotion, Low Power Mode, or thermal throttling; rendering degrades independently.

---

## 18. Testing Strategy

### 18.1 Test layers

#### Unit tests

Required for:

- fixed-point movement;
- turning/alignment;
- tank-vs-terrain collision;
- all weapon collision matrix entries;
- equipment/terrain interactions;
- pickup effects and caps;
- status timers;
- AI target scoring and deterministic tie breaks;
- EnemyDirector finite counts;
- win/loss simultaneous-event rules;
- save migrations;
- content validation;
- swept-collision/tunneling cases (fastest weapon versus a single quadrant, a crossing projectile);
- buffered turns executing ticks after the press.

#### Simulation integration tests

Run complete headless stage fixtures with scripted inputs and assert:

- final checksum;
- event sequence;
- entity counts;
- base/player state;
- enemy counts consumed;
- absence of invalid positions.
- a test-only two-`PlayerID` fixture accepts independent tick command streams and produces stable checksums without any network or second local-input implementation;
- serializing the world mid-run, restoring, and continuing produces checksums identical to an uninterrupted run (ADR-0003).

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
- save/load behavior;
- backgrounding mid-stage pauses gameplay, writes the suspended session, and resumes deterministically.

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

The real-device release gate runs on CI-attached hardware where available; otherwise it is a documented manual checklist executed on the floor device before merging to a release branch.

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
- ADR template and agent handoff template;
- simulation clock-driver decision record (display-link accumulator owned by the application adapter);
- canonical stable-ID registry seeded for weapons, equipment, pickups, enemies, stages, and themes.

Exit criteria:

- project builds without warnings or resource errors;
- non-interactive test commands succeed locally and in CI;
- forbidden domain dependencies are detected by a simple architecture check;
- invalid sample content fails with actionable errors.

### A0: Style-Lock Masters

A0 gates the M1 arena-dimension ADR; it may run in parallel with early M1 engineering.

Deliverables:

- recorded owner authorization covering Phase 0 of `ASSET_PRODUCTION_MANIFEST.md` only;
- one player-tank master, one enemy master, one terrain sample, and the minimum-iPhone readability board produced through the Phase 0 controlled redraw workflow;
- readability captures on the pinned floor device (ADR-0004).

Exit criteria:

- Phase 0 masters exist with complete provenance records;
- the M1 legibility gate can run with representative silhouettes instead of debug art.

### M1: Movement Lab

Deliverables:

- fixed-tick simulation kernel;
- deterministic RNG and checksums;
- universal 56×27 arena bounds (ADR-0009) and terrain grid;
- one player tank;
- four-direction movement;
- collision, buffered turns, and alignment assistance;
- debug renderer and movement replay.
- fixed SpriteKit full-map presentation on the floor-device simulator and one real floor-class iPhone;
- serialize→restore→resume checksum test;
- inert `TankState` fields for turn-buffer and ice-slide state present from the first golden.

Exit criteria:

- identical replay produces identical checksum across repeated runs;
- tank cannot enter solid terrain or leave bounds;
- corridor turning passes touch, keyboard, and controller input scripts;
- 30-minute soak test shows no positional drift.
- the full arena and player remain visible and legible with no camera movement;
- mid-run serialize/restore/resume produces checksums identical to an uninterrupted run.

### M2: Combat Lab

Deliverables:

- normal fire;
- four special weapon families;
- ammunition and cooldowns;
- brick/steel damage;
- projectile/projectile, terrain, tank, and base collisions;
- weapon debug panel;
- complete collision-matrix tests.

Exit criteria:

- every listed collision category has a passing test;
- no frame-time-dependent projectile differences;
- weapon identities are distinguishable in blind control tests;
- stress fixture meets simulation target;
- tunneling tests pass for the fastest configured weapons.

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

Entry dependency: recorded authorization for asset-production Phase 1.

Deliverables:

- VS-01, VS-02, VS-03;
- all weapons and equipment in representative scenarios;
- campaign difficulty profiles;
- elite/director phase;
- final replacement visual language for one theme;
- complete screen flow and checkpoint save;
- settings, accessibility baseline, controller support;
- external playtest build;
- lifecycle interruption handling and suspended-session resume.

Exit criteria:

- three-stage run is complete, restartable, and save-safe;
- all design pillars are demonstrated;
- solo novice and experienced touch playtests can read and recover from at least one base crisis;
- no critical or high-severity test issue remains;
- performance and export targets pass;
- lifecycle interruption tests pass;
- the campaign-spanning three-stage replay passes using chained `initial_session_state` headers.

### M5: Campaign Production

Deliverables:

- 12 stages and 4 themes;
- all 20 enemy types;
- campaign pacing and progression;
- full audio/art replacement set;
- score and optional challenge targets;
- onboarding and localization-ready text.

Exit criteria:

- all stages pass solo completion testing on touch and at least one external controller;
- no enemy/pickup/equipment content is unused without explanation;
- difficulty curves meet playtest targets;
- campaign checkpoint migration tests pass;
- full-campaign stress/performance targets re-validated on the floor device.

### M6: Release Candidate

Deliverables:

- performance, accessibility, input, save, and export hardening;
- credits and rights audit;
- crash/error reporting strategy appropriate to distribution;
- App Store-ready iPhone packaging plus iPad and macOS build smoke coverage (V1's App Store build is iPhone only — ADR-0028);
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
| Equipment/terrain interaction | traversal profiles, ice, and water exit | M3 | interaction matrix |
| Readable power and danger | snapshot/event presentation | M4 | accessibility/readability review |
| Three-stage fun loop | level content and progression | M4 | full-run playtest matrix |
| Multi-agent compatibility | dependency boundaries and task ownership | M0 onward | architecture check + scoped handoffs |
| Future two-player online readiness | stable PlayerID, deterministic commands/snapshots/replay, serializable world state | M1 onward | repeated cross-run checksums + two-command-stream core fixture + serialize/restore/resume test |

---

## 20. AI-Agent Work Packages

Work packages are dependency-aware ownership units. An agent receives one package or a narrower child task.

| Package | Primary ownership | Depends on |
|---|---|---|
| WP-000 Bootstrap | project, CI, docs templates | none |
| WP-010 Simulation Kernel | `Sources/GameCore/Simulation/`, `Sources/GameCore/Model/` | WP-000 |
| WP-020 Content System | schemas, loader, validation | WP-000 |
| WP-030 Terrain and Movement | terrain/movement systems and tests | WP-010, WP-020 |
| WP-040 Combat | weapons/projectiles/fire/collision tests | WP-030 |
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
- GE-026 Encode drop tables and the universal `ArenaSpecification`.

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
- GE-064 Implement Rapid, Fire, AP, and Explosion behavior.
- GE-065 Implement collision matrix validator and tests.

### Game loop

- GE-080 Implement stable PlayerID, V1 player activation, death, lives, respawn, and elimination.
- GE-081 Implement base shield and objective system.
- GE-082 Implement pickup spawning, grace period, collection, and effects.
- GE-083 Implement equipment traversal interactions.
- GE-084 Implement EnemyDirector finite composition and spawn processes.
- GE-085 Implement EnemyBrain baseline movement, target, and fire decisions.
- GE-086 Implement navigation profiles and terrain invalidation.
- GE-087 Implement mid-stage suspend snapshot save/restore and lifecycle pause integration.

### Presentation and UX

- GE-100 Implement the universal 56×27 arena and uniform full-map viewport in SpriteKit.
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
| AI becomes omniscient | Unfair difficulty | World query limits, reaction intervals, no future-input access |
| Canonical data becomes inconsistent | Runtime bugs across agents | Text schemas, fail-fast validator, stable IDs |
| Original assets create distribution risk | Release blockage | Replacement assets and provenance ledger from the start |
| Scope expands to online or non-Apple ports too early | Vertical slice never stabilizes | Explicit deferred scope and adapter extension points |
| Other AI models recommend conflicting redesigns | Planning churn | Review feedback must cite requirement IDs and propose ADRs |

---

## 24. Open Questions That Do Not Block M0–M2

These are intentionally open and must not be guessed into fixed product rules prematurely:

1. Final commercial title and visual identity.
2. ~~Exact campaign base durability and authored repair-event frequency.~~ Resolved — GAME_RULES §11.1.
3. ~~Exact movement base speed and turn-assistance window.~~ Resolved — GAME_RULES §4.1/§4.2.
4. ~~Exact weapon per-level damage/cooldown arrays.~~ Resolved — GAME_RULES §5.3.
5. ~~Whether a limited continue option exists after the V1 player exhausts all lives.~~ Resolved — GAME_RULES §11.3: a failed attempt retries the stage from its entry checkpoint (unlimited); the arcade coin-continue flow is out of V1.
6. ~~Final score economy and extra-life thresholds.~~ Resolved — GAME_RULES §13/§11.3 (score-earned lives off).
7. ~~Exact pacing, ordering, and optional branching among the fixed twelve campaign stages.~~ Budgeted in GAME_RULES §14.1; the maps themselves are still to be authored.
8. ~~Whether foliage blocks AI perception, only presentation, or both in selected stages.~~ Resolved — GAME_RULES §7.5: it does not block AI perception.

Closed by version 2.2: weapon-switch ammunition retention is fixed at full retention (a `retention_percent` ruleset parameter, default 100, preserves balance flexibility); the minimum-device floor is fixed by ADR-0004 and may only widen after the M1 gate, never shrink silently.

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
- [ ] ADR-0001 through ADR-0004 are accepted and reflected in this document.

Before M4 vertical-slice review, confirm:

- [ ] Three stages are playable end to end in single-player.
- [ ] All four special weapons and both equipment types have test coverage.
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
