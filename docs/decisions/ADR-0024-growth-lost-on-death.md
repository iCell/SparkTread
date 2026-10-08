# ADR-0024: A death costs the tank's growth

Status: Proposed (owner decision recorded)
Date: 2026-10-09
Related: GAME_RULES R5.11 §11.3, appendix B.8; ADR-0013 (campaign checkpoints)

## Context

GAME_RULES R5 §11.3 had a respawned tank keep its speed level, power level
and equipment (only armour reset to 3). The owner, playing on the device,
found that wrong: 如果死亡重生的时候，坦克的加成应该都没了才是 — the classic
rule, where a lost tank's stars are lost with it.

## Decision

1. When a player tank dies with reserves left, the replacement spawns with
   speed level 1, power level 0 and no equipment
   (`LifecycleRules.respawnSpeedLevel` / `respawnPowerLevel`), armour 3 and
   the usual spawn protection, after the usual 60 ticks.
2. The current special weapon and its ammunition are inventory, not
   growth, and stay with the player (Claude's reading of 加成; the owner may
   extend the reset to them).
3. Stage hand-over (§11.3 通过关卡) and retry from the checkpoint are
   unchanged: what the LIVE tank has at a stage's end still carries.
4. `PlayerState.retained*` records the reset values at death rather than
   the dead tank's, so a snapshot taken during the respawn countdown
   resumes the same way. Replay format 13 → 14.

## Alternatives considered

- Keep growth (the previous rule): the owner rejected it on feel.
- Also drop the special weapon and ammo: offered as the owner's call; not
  taken by default because ammo is a stock the player spent pickups to
  build, and §11.3 keeps inventory across stages too.

## Gameplay consequences

A death is costly again: a maxed tank returns as a rookie, and the power
and speed pickups matter every life. §17 should watch whether stages 6+
become too punishing with it.

## Architecture consequences

GameCore only (`Stage.processDeaths`, `LifecycleRules`); the replay
version bump in GameApplication; no content change.

## Migration cost

Format-13 recordings are rejected, as every bump has done.
