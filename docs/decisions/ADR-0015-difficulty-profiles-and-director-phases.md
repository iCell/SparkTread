# ADR-0015: Difficulty Profiles and Authored Director Phases

Status: Proposed (drafted 2026-09-10 late evening, M4 item 4)

Date: 2026-09-10

Related: plan §5.1, §10.2, §10.6–10.7, §11.3, §6.6, §16.3, §22.3; ADR-0005 (`allied_base_damage` is difficulty data); ADR-0013 (campaign run); `GAME_RULES.md` §9.2 (the reference's five-level table, research only)

## Context

Plan §10.7 fixes the INTENT of three presets (Casual, Standard, Veteran)
across targeted behaviour, base focus, enemy special ammunition, reaction
interval, coordination, telegraph duration, composition and allied base
damage, and says "Exact numbers live in `DifficultyDefinition`". §10.6
forbids difficulty from raising speed beyond collision reliability or
telegraphs below the fairness floor; §22.3 makes "more enemies" a last
resort. §10.2 gives the director "pressure pacing and elite timing";
§11.3 VS-03 wants "an elite wave with a protected mine-layer or terrain
breaker" and "base shield/repair opportunity before final pressure"; §6.6
makes base repair "a stage-authored director effect". Before this ADR the
enemy brain's cadence (30 ticks), base-focus rolls, fire duty cycles and
mine roll were constants, the director a flat queue, and only
`WeaponRuleset.alliedBaseDamage` was difficulty-shaped.

## Decision

1. **`EnemyBehaviorProfile`** (GameCore rules data): decision interval,
   base-focus percent scale, wander percent, fire-window percent (scales
   the open part of each aligned/break duty cycle, clamped to the cycle),
   mine-place percent, course-commit percent; `.standard` is the previous
   behaviour. It is STAGE STATE (`StageState.enemyBehavior`), checksummed
   and range-checked, so worlds, replays and snapshots are
   self-describing and the brain never branches on a difficulty id.
   Speed and armour are not touched (§10.6).
2. **`DirectorPhase`** (GameCore, stage state): `afterSpawned`,
   `reinforcements` (pushed to the FRONT of the spawn queue, carried
   pickups kept paired), optional `maxAliveEnemies`, `repairsBase`
   (durability to full; a destroyed base stays destroyed). Phases fire
   once each, in order, at the director pass after the trigger count is
   reached; `directorPhaseStarted` and `baseRepaired` events drive a HUD
   notice ("精英布雷车来袭 ×3") and cues. VS-03 authors one phase: after 16
   enemies, `mine_c` escorted by two `ap_c`, cap 6, base repaired — the
   base-shield carrier precedes it.
3. **`DifficultyDefinition`** (content, `Content/difficulties/*.json`,
   ids from the registry): the behaviour profile, telegraph percent
   (floored at 45 ticks), a composition variant (`forgiving` C/D → A/B,
   `baseline`, `advanced` every third A/B → C/D — variants, never counts),
   `alliedBaseDamage` (Off/On/On per ADR-0005), and the plan's enemy
   special-ammo percent recorded for the header (enemies are
   ammunition-exempt, §6.4 — no effect yet). Values: Casual 40-tick
   decisions, 70 % focus, 20 % wander, 70 % fire, 140 % telegraph;
   Standard = authored; Veteran 20-tick decisions, 125 % focus, 5 %
   wander, 140 % fire, 30 % mines, 40 % commit. The builder applies the
   definition; the content validator requires the three presets.
4. **Selection and identity.** `CampaignRun.difficultyID` (fixed for a
   run; saved runs without it decode as standard); the stage-select
   screen has a 休闲/标准/老兵 picker that shapes new runs, while a
   checkpoint keeps its own; the replay header names the difficulty
   (format 5, the mine roll and cadence changed same-input behaviour).
   The stage provider hands the session the difficulty's weapon rules.

## Consequences

- Replay format 5; the M1 movement golden (no enemies) is unchanged.
- Coordination ("role behaviour") and predictive targeting are not
  modelled — the profile has no field for them yet; base repair does not
  rebuild the fort ring (the shield's domain).
- Open for the owner: the preset numbers (playtest), whether the
  reference's five levels should seed more presets, the default preset
  (standard), and whether difficulty may change mid-campaign (fixed per
  run here).
