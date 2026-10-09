# ADR-0026: A lone quadrant crumbles, and the fort comes back whole

Status: Proposed (owner decision recorded)
Date: 2026-10-09
Related: GAME_RULES R5.14 §3.2 item 5, §11.2, appendix B.11

## Context

Two things the owner saw on the device. A quarter-brick — one quadrant of
a cell — standing alone in a cleared gap, which the quadrant strip of
§3.2 can leave behind and which looks like debris that should have gone.
And the fort: a base shield taken over damaged walls hardened them, and on
expiry §11.2 restored "the recorded original" — the damage included —
where the owner expects the classic behaviour, the walls back whole.

## Decision

1. §3.2 item 5: when a hit removes a quadrant and the cell is left with
   exactly one, that quadrant falls with it and the cell reveals its
   surface, cracks cleared. Applies to every destructible wall kind, in
   `Combat.settleTerrainChanges` AFTER a strip or a blast has taken all
   its quadrants — never inside the strip, where an emptied cell would let
   later columns pass through to the material behind against §3.2's
   "first material".
2. §11.2: at first activation the fort records a RESTORE TARGET, not the
   standing state — a brick-family cell as the same kind whole and
   uncracked (surface kept); a cell shot away as the template's authored
   kind, whole, which `StageState.fortTemplateKinds` carries from the
   content (`StageBuilder`); steel, water and white steel as they stand.
   Expiry restores that target through the existing quadrant-aware
   restoration (blocked quadrants still wait).
3. Replay format 15 → 16 (both change the simulation).

## Alternatives considered

- Whole-cell damage instead of quadrants: changes the wall model the
  whole R5 rulebook is built on; rejected for the targeted crumble.
- Repairing the fort on activation rather than on expiry: the hardening
  already covers every template quadrant with steel, so the player sees
  no difference during the shield; the repair on expiry is what matters.

## Gameplay consequences

Gaps clear cleanly; a base shield doubles as a fort repair, as in the
genre's original — a tactical reason to hold the shield pickup.

## Architecture consequences

GameCore (`Combat`, `Stage`, `StageState`, checksum) and the builder;
content unchanged (the validator already requires brick templates).

## Migration cost

Format-15 recordings are rejected, as every bump has done.
