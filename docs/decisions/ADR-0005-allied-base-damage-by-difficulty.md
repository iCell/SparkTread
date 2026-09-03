# ADR-0005: Allied Base Damage Scoped by Difficulty

Status: Accepted  
Date: 2026-09-01  
Supersedes: the blanket allied-base-damage prohibition in D-010 (plan v2.2)

## Context

Plan v2.2 disabled allied damage to the player's own base at every difficulty. The owner has decided the immunity should be a Casual-only assist: on Standard and Veteran, the player's own fire can damage the base, restoring the reference game's positioning tension around the objective for players who opt into higher difficulty.

## Decision

1. `DifficultyDefinition` gains a boolean `allied_base_damage`: Casual `false`, Standard `true`, Veteran `true`. It is ruleset data — combat code never branches on difficulty identity.
2. The flag governs every allied damage source against the base — projectile, explosion, fire hazard, and mine — and overrides team-based exemptions for the base object only.
3. When enabled, an allied hit on the base uses a distinct own-fire cue (visual + audio) so self-inflicted damage is never mistaken for an enemy breakthrough; stage-authored repair events remain the recovery path.
4. Allied damage to allied tanks — including the future co-op partner — remains disabled; this ADR concerns the base only.

## Alternatives considered

- Blanket immunity at all difficulties (v2.2 status quo): rejected by owner decision — removes a meaningful risk dimension from Explosion/Mine play near the base on higher difficulties.
- Blanket allied damage at all difficulties (reference behavior): rejected — self-destroying the base is a classic frustration for casual players and contradicts the Casual preset's intent.

## Gameplay consequences

Explosion radius, mine placement, and firing lanes near the base become genuine positioning decisions on Standard and Veteran; Casual keeps the forgiving objective. Difficulty descriptions and tutorials must state the rule.

## Architecture consequences

One boolean read at base-damage resolution (tick step 10), before weapon damage applies. No new collision categories; no code branching outside the data flag.

## Migration cost

Zero: applied before implementation begins. Content validator requires the field on every difficulty definition.

## Tests affected

Collision-matrix base cases run under both flag states; difficulty-data validation; a scene test asserting the own-fire cue fires only for allied hits with the flag enabled.
