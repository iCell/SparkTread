# ADR-0027: The extra life weighs more while the reserves are at one or none

Status: Proposed (owner decision recorded)
Date: 2026-10-09
Related: GAME_RULES R5.18 §10.2, §17 item 7, appendix B.15; ADR-0025 (lives and the drop scale); ADR-0023 (brick drops)

## Context

The owner, after playing the eased difficulties (R5.15–R5.17): "如果当下的
生命只有 1，则优先提高获取到加命装备的几率". The drop table (ADR-0025) gives
the extra life 1 of 15 entries, so on standard an ordinary kill yields a
heart about 0.7 % of the time (10 % × 1/15), wherever the player stands.
A player on their last reserve rarely sees one before the run ends.

## Decision

1. `DropRules.lowReservesThreshold` = 1 and
   `DropRules.extraLifeWeightScaleAtLowReserves` = 6 (GameCore). While the
   fewest reserves among the active players is at or under the threshold,
   every `extra_life` entry of the stage's drop table counts six times in
   the CHOICE an enemy-death drop makes. The roll (dropChancePercent) is
   unchanged: the bias moves what drops, not how often.
2. The choice stays one draw of the `drop` stream: the draw is over
   `table.count + extraWeight`, and an index past the table's end is the
   extra life. Above the threshold `extraWeight` is 0, so the draw is the
   table's own index exactly as before — replays from before R5.18 move
   only where a drop was rolled at low reserves.
3. Brick drops (ADR-0023) still exclude the extra life and are untouched.
4. Replay format 16 → 17. No golden moved (the M1 lab has no stage; the
   chained campaign replay is scripted instant wins).
5. Threshold and weight are the owner's provisional numbers; GAME_RULES
   §17 item 7 watches them, veteran in particular (it starts at one
   reserve, so the bias is on from its first kill).

## Alternatives considered

- Raising the drop RATE at low reserves: more pickups of every kind would
  also arrive; the owner asked for the extra life to be favoured.
- Guaranteeing a heart after N kills at one reserve: a pity timer is a
  second mechanism with state to save and replay; the weight does the
  job inside the existing draw.
- Threshold 0 (only the very last tank): the owner's words were "只有 1",
  the HUD's reserve count; 0 is included since it is worse.

## Gameplay consequences

With the standard table, a drop at one reserve is a heart 30 % of the
time instead of 6.7 %. Casual's five reserves rarely reach it; veteran is
in it from the start until its first 1UP.

## Architecture consequences

GameCore only (`DropRules`, `Stage.drawDrop`, `Stage.fewestReserves`);
GameApplication bumps the replay format. No content change.

## Migration cost

Replays of format 16 are refused, as every bump before. Saves unchanged.

## Tests affected

`LowReserveDropBiasTests` (share at reserves 1 / 0 / 2 over 6000 draws;
the draw above the threshold equals the table index; a life-less table is
unchanged; a kill at one reserve spends roll, choice and placement as
before). `ReplayRecordingTests` pins format 17.
