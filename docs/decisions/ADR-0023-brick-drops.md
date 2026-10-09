# ADR-0023: Breaking brick can drop a pickup

Status: Proposed (owner decision recorded)
Date: 2026-10-08
Related: GAME_RULES R5.10 §10.5, §12 step 7, §17 item 5; ADR-0018 (rules authority)

## Context

GAME_RULES R5 had three sources of pickups: ordinary enemy drops by the
stage's table, carriers' guaranteed drops, and hidden pickups revealed
when their walls fall. Breaking brick itself yielded nothing. The owner
asked (2026-10-08) that breaking brick can randomly drop equipment, chose
3 % per cell and no difficulty tiers, and left the rest of the shape to
Claude's proposal, which they did not amend.

## Decision

1. A brick-family cell (red or white) whose four quadrants a PLAYER's
   round has just emptied rolls once for a drop; quadrant hits, cracks and
   enemy rounds roll nothing. Fort-template cells and cells covering a
   hidden pickup's area are never candidates.
2. The chance is `brickDropChancePermille` per cell (default 30 = 3 %, the
   owner's number; both brick tiers; no difficulty scaling), with a stage
   cap `brickDropCap` (default 2). A capped stage rolls nothing more.
3. The roll runs in §12 step 7 after the deaths' drops, over the tick's
   cleared cells in (y, x) order, one `drop` draw per cell (0…999 against
   the permille) and a second draw to choose only on a hit, from the
   stage's drop table minus `extra_life`. An empty filtered table drops
   nothing.
4. The request is placed by §10.2's legality and reachability, at the
   legal 2×2 area whose centre is nearest the cleared cell's (ties to the
   smaller (y, x)), spending no draw; lifetime and pickup rules are the
   usual ones.
5. State: `StageState` gains the chance, the cap, the granted count and
   the tick's cleared cells (always empty at a tick's end); `PendingPickup`
   gains `preferredCell`. All are in the checksum and the invariants. The
   replay format is 13.
6. Stage JSON: optional `brickDropChancePermille` and `brickDropCap`,
   validated to 0…1000 and ≥ 0; absent means the defaults, so the twelve
   stages are unchanged.

## Alternatives considered

- Roll per quadrant hit: rewards rapid fire and explosion with more rolls
  for the same wall; rejected for the whole-cell rule.
- Count enemy rounds: enemies would gift pickups by chewing walls, outside
  the player's control; rejected.
- Separate brick drop table: a second thing for content to maintain;
  rejected in favour of the enemy table minus extra lives.
- Place at random like other drops: loses the "it came out of the wall"
  read; rejected for nearest-legal-area placement.
- Difficulty tiers (2/1.5/1 %): offered, declined by the owner.

## Gameplay consequences

A stage of 250–400 brick cells, of which ordinary play clears 60–120,
yields about 2–4 hits and, after the cap, at most 2 drops — a minority
beside the ~4 enemy drops of a standard stage. §17 item 5 watches whether
it tempts wall farming.

## Architecture consequences

GameCore `Combat.applyStrip` notes cleared cells (with the shooter's
owner), `Stage.rollBrickDrops` rolls them, `placePendingPickups` honours
the preference. GameApplication's schema, builder and validator carry the
two fields; `ReplayRecording.currentFormatVersion` 12 → 13, goldens
regenerated with the review-log note ADR-0018 requires.

## Migration cost

Recordings of format 12 are rejected, as every version bump has done;
suspended sessions carry the world verbatim and the new fields default on
decode only through the builder, so a snapshot made before this change is
rejected by its format version rather than mis-read.

## Amendment 2026-10-09: half the chance, placed at random

Owner, after a device session: the drops felt too frequent — halve them —
and a brick drop should not appear where the brick was but scatter at
random among the places a drop can appear. The default chance is now
15 ‰ (1.5 %), the cap stays 2, and a brick drop is placed exactly like
every other drop (§10.2, a `drop` draw among the legal areas);
`PendingPickup.preferredCell` and the nearest-area branch are gone.
Decision items 2 and 4 above are superseded accordingly. Replay format
14 → 15. The ordinary drop rate was halved the same day (ADR-0025
amendment).
