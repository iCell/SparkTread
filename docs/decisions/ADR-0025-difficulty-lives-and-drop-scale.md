# ADR-0025: Starting lives and the random drop rate follow the difficulty

Status: Proposed (owner decision recorded)
Date: 2026-10-09
Related: GAME_RULES R5.12 §10.2, §11.3, appendix B.9; ADR-0015 (difficulty profiles); ADR-0023 (brick drops)

## Context

Asked how often the extra-life heart drops, the content answered 0 %: all
twelve stages shipped (2026-10-03) with an empty `dropTable` and
`dropChancePercent` 0, so ordinary kills never rolled a drop and every
pickup came from carriers, hidden treasures and fixed spawns — which also
left ADR-0023's brick drops, drawn from the same table, inert. The owner
then decided: random drops should vary with difficulty, and a new run's
reserves should be 5 / 3 / 1 for casual / standard / veteran.

## Decision

1. `DifficultyDefinition` gains `startingLives` (5 / 3 / 1) and
   `dropChancePercentScale` (150 / 100 / 50 percent); absent in a file
   means 3 and 100. Validated 0…99 and 0…400.
2. A run started from the select screen begins with the chosen
   difficulty's `startingLives` (`SessionState.campaignStart(lives:)`,
   read by `AppFlowModel` from the bundled profiles at launch). The
   checkpoint of a continued run carries whatever it had.
3. `StageBuilder` sets the stage's `dropChancePercent` to the authored
   value scaled by the difficulty, capped at 100; the simulation is
   unchanged (the chance was always content), so the replay format stays
   at 14.
4. Stages 2–12 author `dropChancePercent` 20 and one weighted table —
   armor ×3, ammo crate ×3, speed ×2, power ×2, base shield, freeze, bomb,
   invincibility, extra life ×1 (15 entries) — so an extra life is
   1/15 × 20 % ≈ 1.3 % per ordinary kill on standard (2 % casual, 0.7 %
   veteran), beside the three authored hearts of stages 7, 11 and 12.
   Stage 1 keeps the reference's channels (carriers and hidden treasures,
   no natural roll). Brick drops (ADR-0023) draw from the same table
   minus the extra life and are not difficulty-scaled (the owner's call
   on 2026-10-08).
5. Reference evidence recorded the same day (BV14b411K7bv part 1, the
   reserve icons under the score): reserves carry across stages, a 1UP
   adds one, and a Game Over's continue restarts at 3 — §11.3's carry
   rule matches the original.

## Alternatives considered

- Scaling only the extra-life weight by difficulty: the owner asked for
  the random rate as a whole; a single scale keeps one table per stage.
- Difficulty-scaled brick drops: declined by the owner on 2026-10-08.

## Gameplay consequences

Casual has five reserves and half again the drops; veteran one reserve
and half the drops. Deaths now also cost growth (ADR-0024), so veteran
is markedly harder. §17 watches both.

## Architecture consequences

GameApplication content layer only, plus the flow model reading the
profiles at launch. No simulation change.

## Migration cost

None: old difficulty files decode with the defaults.
