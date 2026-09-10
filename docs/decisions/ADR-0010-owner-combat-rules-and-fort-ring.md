# ADR-0010: Owner Combat Rules — Special-Channel Fallback, Fort-Ring Hardening, Hidden-Treasure Reveal, Mine Visibility

Status: Accepted by the owner on 2026-09-10 (drafted 2026-09-09 during the Claude/PI joint review); restoration mapping decided as B — recorded materials  
Date: 2026-09-09  
Related: plan §6.6, §8.1, §9.3, §11.2, §12.3; ADR-0005

## Context

Several gameplay behaviours in the M3 slice were introduced on direct owner
requests recorded only in code comments and tests ("owner request", "owner
rule"). They deviate from, or extend, `PRODUCT_IMPLEMENTATION_PLAN.md`, and
two independent agents flagged that a deviation the plan does not describe
must be recorded as a decision rather than left implicit (§1.5, §20.4). The
joint review also fixed defects in the same mechanisms (entombment by the
fort ring, treasures revealing under steel) whose fixes need a stated policy.

Evidence of the owner requests:

- depleted special channel falls back to the normal round —
  `Tests/GameCoreTests/CombatTests.swift` (`depletedSpecialFallsBackTo
  NormalRound`, "owner request"), `Combat.processFireRequests`;
- base shield hardens the fort ring to steel and expiry rebuilds it —
  `Tests/GameCoreTests/StageTests.swift` (`freezeBombShieldAndLifePickups`,
  "shovel rule"), `Stage.hardenBaseFortRing`;
- enemy mines cloak once armed — `MovementLabScene.syncMines` ("owner rule");
- drops appear elsewhere on the map — owner message of 2026-09-09 after the
  first physical-device session ("掉落出来的装备应该随机出现在别的地方").

## Decision (proposed — each item takes effect as a decision only on owner acceptance)

The numbered items describe the behaviour the code implements today
(items 1, 2, 3, 5, 6) or offers as data (item 4). Recording them here does
not change any gameplay default; it makes them reviewable.

1. **Special-channel depletion falls back to the normal round.** When a
   player presses special fire with less ammunition than the weapon's
   `ammo_cost`, the press fires the NORMAL weapon through the normal
   channel instead of producing a dry-fire. If accepted, this supersedes
   plan §8.1 "the input produces a dry-fire event and no projectile" for
   the player only (AI is ammunition-exempt). The fallback shares the normal
   channel's cooldown and active cap and costs no ammunition. Consequence to
   be accepted together with the rule: the special button is hold-based, so
   holding it with empty ammunition auto-fires the normal cannon at its
   cooldown cadence, while the normal button itself stays edge-triggered.
2. **Base shield hardens the fort ring.** Collecting `base_shield` extends
   the shield (§6.6 refresh/extend, ruleset data) AND rewrites every fort
   ring cell (the in-bounds, non-border cells of the 4×4 box around the
   2×2 base) to full steel; damaged steel is rebuilt whole. On expiry every
   ring cell is rebuilt as full brick (the reference "shovel" behaviour).
3. **Occupied cells are never rebuilt** (plan §6.6): a ring cell whose
   area overlaps any tank footprint, any mine's hardware box (ruleset
   extent) or a pickup's cell is skipped at hardening and at expiry and
   keeps its current state; there is no later retry.
4. **Restoration mapping is ruleset data.** `PickupRuleset.
   fortRingRestoresRecordedKinds` is `true` by default since the owner's
   2026-09-10 decision ("应该是 B 恢复为加固前记录的材质"): a hardened cell
   is restored to the material recorded at activation; `false` restores
   brick unconditionally (the previous default, kept as data).
   When set to `true`, cells recorded as steel or water at activation are
   restored as themselves instead of brick. The record lives in
   `BaseState.fortRingRestore` (serialized, checksummed), is taken only on an
   inactive→active transition and cleared after expiry; a shield that
   started active without hardening restores nothing. Enabling the flag for
   the campaign is a separate owner decision.
5. **Hidden treasures reveal when the covering cell could hold a pickup**
   (`TerrainKind.canHoldPickup`: ground, ice, foliage), the same legality
   used for placement. A covering brick that merely changes material (fort
   hardening to steel) keeps the treasure hidden. The stage record is
   consumed only once the pickup was actually placed; a failed placement is
   retried on later ticks.
6. **Mine visibility (presentation only).** Enemy mines are drawn at full
   opacity while arming, then cloak; a tank within four cells makes them
   faintly readable (0.3), within two cells more so (0.55). The player's own
   mines never drop below 0.6 opacity. Ownership and level stay readable
   through the delivery's badge and digit (§12.3), never through colour.
7. **Drops appear at a random legal cell** (owner rule 2026-09-09, the
   reference behaviour): a carrier's item and a kill-roll drop spawn at a
   random interior cell drawn from the `drops` RNG stream (up to eight
   draws, never under the base structure or a tank, then the usual ring
   scan), falling back to the death cell. If accepted, this supersedes the
   plan §9.3 sentence "a drop spawns at the defeated enemy's cell center".
   The plan behaviour remains available as `PickupRuleset.
   dropsSpawnAtRandomCells = false`. Hidden treasures and authored starter
   pickups keep their fixed cells.

## Alternatives considered (drafted by the reviewing agents; the owner may prefer any of them)

- Keep dry-fire on depletion (plan §8.1): not what the owner asked for when
  the fallback was requested (recorded as "owner request" in the tests);
  the rationale the agents infer is that a dead trigger reads as a broken
  button — owner confirmation needed.
- Edge-trigger the special button when depleted: not adopted in the current
  implementation — the cooldown already bounds the auto-fire, and rapid's
  identity is a held button.
- Rebuild occupied cells later ("retry"): not adopted — undocumented
  deferred terrain changes are hard to read and to test; the skip is
  deterministic.
- Preserve authored steel by default: deferred to the flag in item 4 — it
  changes campaign terrain outcomes and needs the owner's explicit call.
- Reveal on any non-brick kind: not adopted — a treasure under a hardened
  steel cell would spawn beside the wall.

## Gameplay consequences

Items 1–2 are the behaviours the owner has been playing since M3; 3 and 5
remove two defects (a tank entombed in steel; a treasure appearing under
steel); 4 changes nothing until enabled; 6 is readability only; 7 moves
every drop away from the kill site (the owner's explicit request). Accepting
this ADR changes no default; declining item 1 or 2 would require a code
change back to the plan's text.

## Architecture consequences

`PickupRuleset` (GameCore/Rules) carries the tunables; `BaseState` carries
the restoration record; no layer boundaries change.

## Migration cost

Zero content changes. The checksum surface gained `BaseState.fortRingRestore`
and `burnCooldownTicks` (M1 golden regenerated with a review note).

## Tests affected

`CombatContractTests` (fort ring occupancy, refresh record, restoration
mapping under both flag values, damaged steel hardening, hidden treasure
under steel and retry), `CombatTests` (`depletedSpecialFallsBackToNormal
Round`, `emptySpecialAmmoNeverFiresTheSpecialWeapon`), `StageTests`
(`freezeBombShieldAndLifePickups`).
