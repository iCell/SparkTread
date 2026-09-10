# ADR-0012: Reference Results Table and Stage-Clear Bonuses

Status: Proposed (awaiting owner acceptance; drafted 2026-09-10 on the owner's decision "5，按照原作来")  
Date: 2026-09-10  
Related: plan §11, §12.2; `GAME_MECHANICS_SPEC.md` §8.2 (reward category column), §11; ADR-0011 (stage transitions); `docs/CURRENT_REVIEW.md` "Stage-clear results table and bonuses"; `Tools/reference_measure/results_screens.py`

## Context

ADR-0011 left the reference's stage-clear "Reward" unimplemented as a
scoring rule needing its own owner decision. The owner decided on
2026-09-10 that it follows the reference ("按照原作来"). The reference's
results screens were then surveyed in the owner's gameplay recording
(the first 30 of its 32 stages; the video's last 9 % failed to download):
`Tools/reference_measure/results_screens.py` finds every "Mission
Complete" screen and crops the reward text, the finished panel, the score
counter before and after, and the next stage card, for reading by eye.

What the screens show:

- **Table.** Title "战斗成绩"; a line "MaxHits N   MaxCombos N"; FOUR rows,
  each with two tank icons and their kill counts, a multiplier label
  "×1 =" … "×4 =" and the row's subtotal; a rule; "总计" with the sum of
  the subtotals. Stage 3, read exactly: (2+2)×1 = 4, (3+0)×2 = 6,
  (2+0)×3 = 6, (1+0)×4 = 4, 总计 20. Every screen checked obeys
  subtotal = (left + right) × row multiplier and 总计 = Σ subtotals.
- **Eight icons = the eight reward categories** of the recovered §8.2
  column (values 0…7). Rows 1 and 4 pair two colour variants of the same
  chassis (the two Normal pairs; the two AP pairs), which is the
  ROW-MAJOR reading of that column: row r holds categories 2r and 2r+1,
  i.e. Normal A/B + Normal C/D (×1), Rapid + Mine (×2), Explosion + Fire
  (×3), AP A/B + AP C/D (×4). This mapping is inferred from the icons'
  shapes and colours, not from attributing each kill in the footage.
- **Two score bonuses per cleared stage.** While the table counts up, the
  score counter gains a CONSTANT (the tally bonus); ≈0.1–0.5 s after the
  total, "Reward +N" rises from the panel title and the counter continues
  to score + N into the next stage's first seconds. Read across the 30
  screens (score before/after the panel, reward text):

  | stages | tally bonus | reward | samples |
  |---|---:|---:|---|
  | 1–10 | 200 | 330 | 485→685 (6 kills, hits 3, combos 3); 3555→3755 (10 kills, combos 1); 16275→16475 (25 kills, hits 7, combos 5) |
  | 11–25 | 600 | 660 | 2165→2765 (30 kills); 48580→49180; 77145→77745 |
  | 26–30 | 1000 | 1000 | 5115→6115; 27030→28030 |

  Neither bonus depends on the total, the kill count, MaxHits or
  MaxCombos. A few before/after differences exceed the bracket value by a
  multiple of 100 (e.g. 23780→25380 at stage 17): the counter animates,
  and a treasure or kill still counting in at the panel's first frame
  inflates the difference; the reward text and the bracket minimum are
  consistent throughout.
- **Ambiguity.** The recording restarts its score twice (continues after
  a game over at stage 11 and at stage 26), exactly where the brackets
  change. The bonuses therefore either grow with the STAGE NUMBER (the
  reading recorded here: 1–10 / 11–25 / 26+) or with something that
  changed at those continues (continue count, lives). The footage cannot
  separate the two; the stage-number reading is the conventional design
  and needs no hidden state.
- **Not measured.** The meaning of MaxHits and MaxCombos (consecutive
  hits? kills within a window?), the per-kill scores, whether the weighted
  total feeds anything (a rank, an extra life), and the reward line's
  sound.

## Decision

1. **Reward categories are archetype data.** `EnemyArchetypes.Attributes.
   rewardCategory` carries the §8.2 column; the results table row is
   `category / 2`, the multiplier `category / 2 + 1`
   (`ScoreRules.rewardMultiplier`). `KillTally` (GameApplication) counts
   kills per category from `tankDestroyed` events and derives row counts,
   subtotals and the weighted total; the panel shows the four fixed rows
   (category labels in place of the reference's icons), the subtotals and
   "总计". Unknown archetype ids count in category 0.
2. **Clear bonuses are stage data.** `ScoreRules` (GameCore, data) holds
   the tier table; `ScoreRules.reference` is 1 → (200, 330), 11 →
   (600, 660), 26 → (1000, 1000). Content gains a REQUIRED `stageNumber`
   (validator: 1…999); the builder writes `ScoreRules.reference.
   clearBonus(stageNumber:)` into `StageState.clearBonus`. Lab and test
   worlds carry `.none`.
3. **Paid on the deciding tick.** `Stage.resolveObjective` adds tally +
   reward to every active player's score when the stage is won, right
   after `stageWon`, and emits `stageClearBonus(tally:reward:)` (only when
   the bonus is non-zero). The bonus is checksummed and bounded by
   `WorldInvariants`; a recording without the key decodes as `.none`.
   A lost stage pays nothing.
4. **Presentation paces the payout.** `StageFlow` gains a `.reward` cue
   `rewardDelay` (18 ticks ≈ 0.3 s) after the total line on a won stage
   with a bonus, and the hold covers it; the controller withholds the
   tally bonus from the HUD score until the total line and the reward
   until the reward line ("奖励 +N"), so the displayed score counts in as
   the reference does while the authoritative score is final at the
   decision. A tally tick plays per row (four rows + total).
5. **Left out, with owner decisions attached:** MaxHits/MaxCombos (no
   semantics), tank icons in the rows (ADR-0011 follow-up), a reward
   sound (no isolated instance in the recording), and the alternative
   continue-count reading — if the owner knows the reference's rule to be
   continue-based, `ScoreRules` needs a continue counter instead of a
   stage-number tier.

## Consequences

- Golden replays are unaffected (lab worlds have no stage); stage-world
  checksums include the bonus. Replay format 3 is unchanged (optional
  key).
- Content schema: every stage JSON must state `stageNumber`; the
  validator reports its absence before the builder runs.
- The HUD's score is a presentation value during the outro (world score
  minus the unpaid bonuses); tests read `controller.hud.score` for the
  paced value and the world for the authoritative one.
- Owner acceptance decides: the stage-bracket reading (default) vs. a
  continue-based rule; whether MaxHits/MaxCombos are wanted and what they
  mean; the category labels vs. icons.
