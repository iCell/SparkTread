# ADR-0021: Owner Rules — Shell Clashes by Strength, Fire Bursts on Any Shell, Doubled Invincibility; Tanks May Leave a Spawn Reservation (GAME_RULES R5.7)

Status: Accepted (owner instructions of 2026-09-15: "敌我两方的弹相遇，两颗都直接消失：这个规则不合理，我们需要修改一下"; asked to choose, the owner answered "按照你说的强弱对抗来，但是如果是火焰弹的话碰到任何弹药都会直接爆炸着火"; then "无敌的时间翻倍"; the stuck reinforcements were reported as "为什么最后来袭了都在本地不动了")  
Date: 2026-09-15  
Related findings / supersessions: amends ADR-0018 (GAME_RULES §6.1, §6.4, §7.1, §9.3, §10.1, §10.4, §14.3)

## Context

R5 made any two opposing shells that meet vanish together, with no blast and no flame, whatever their kind. The owner found that unreasonable: a normal round cancelled an AP or explosion round, and a fire round died silently.

On the same device run the stage-3 elite reinforcements stopped at the top of the map. A spawn process may start on a point a slow tank still stands on (§9.3 lets the process wait), and tank movement and AI steering treated the reservation as solid even for the tank already inside it. Neither could proceed, so the stage could never be won.

## Decision

1. Opposing shells meet by strength (§6.1). Normal and rapid shells are light; AP and explosion shells are heavy; the fire shell is handled on its own. Power level does not matter.
   - Light meets light: both vanish, no effect.
   - Light meets heavy: the light shell vanishes; the heavy shell flies on with all its abilities.
   - Heavy meets heavy: both end with their effect; an explosion shell blasts at its centre at the meeting time, AP simply ends.
   - A fire shell that meets any opposing shell lands its flame at its centre at the meeting time (open-ground footprint, no face clipping) and ends. The other shell follows its own kind: a light shell vanishes, a heavy shell ends with its effect. "爆炸着火" is realised as the fire shell's own flame landing; no blast damage is added.
   - Same-team shells still pass through each other. Ending shells move to the meeting position before their effect; survivors keep flying within the tick and may meet other shells.
2. Invincibility from Who PA Who lasts 1200 ticks (20 s) instead of 600; the refresh rule is unchanged (`PickupRuleset.invincibilityFloorTicks` and `invincibilityRefreshBelowTicks` are 1200). Spawn protection and Flag On Guard durations are unchanged.
3. A spawn reservation still keeps tanks from entering, but a tank whose collision box already overlaps one may drive out (§9.3). Movement and AI steering ignore a reservation the tank overlaps; the spawn check, respawn placement and water-exit placement still treat every reservation as solid.
4. The director phase HUD notice ("精英…来袭 ×N") is removed at the owner's request; the phase's sound cues stay (ADR-0015).

## Alternatives considered

- Both shells vanish but keep their effects: offered; the owner preferred strength.
- Compare power levels: offered; rejected, weapon kind is the readable distinction on screen.
- Opposing shells never interact: offered; rejected, cancelling enemy fire with normal rounds stays a core defence.
- Starting no spawn process on an occupied point: rejected, §9.3 already defines waiting and switching points; the defect was the blocked exit, not the waiting.

## Gameplay consequences

Normal and rapid fire can no longer stop AP or explosion rounds, only other light rounds; the player must dodge or block heavy rounds with walls, or meet them with heavy rounds. Shooting at an incoming fire round sets fire where they meet. Invincibility lasts 20 seconds. Slow enemies no longer freeze on their spawn points.

## Architecture consequences

`Combat.resolveContacts` decides per shell whether a pair contact ends it and with which terminal effect. `Simulation.ObstacleField` gains a `movingWithInset` option used only by movement and AI steering.

## Migration cost

Replay format 10: format-9 recordings and suspended sessions are refused as incompatible. No replay golden moved.

## Tests affected

`R5 shell contacts` (a normal shell against each enemy shell kind; heavy against heavy), `R5 spawning and statistics` (a tank inside a reservation drives out, none enters; a slow enemy on its spawn point does not deadlock the next spawn), the stage-flow integration test for director phases, the replay format boundary.
