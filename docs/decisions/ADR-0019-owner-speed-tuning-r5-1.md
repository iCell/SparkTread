# ADR-0019: Owner Playtest Tuning — Tanks and Shells at 40 % of R5 Speed, Normal Fire Spaced Like R5 (GAME_RULES R5.1 → R5.3, R5.6, R5.8)

Status: Accepted (owner instructions of 2026-09-15 after two device runs: "整体移动和子弹速度都变快了，我觉得应该降低一些", then "还是很快，再慢 50% 试一下", then "普通子弹的密度太大了", then "快枪子弹也比较密集，降低密集度", then, after seeing AP C "能动，但依然很慢，看起来像在爬", "可以快一些")  
Date: 2026-09-15  
Related findings / supersessions: amends ADR-0018 (GAME_RULES R5 §4.1, §5.2, §5.3, §9.1, §17 item 4)

## Context

R5 raised the player base speed from 2880 su/s to 4.8 cells/s (starting at speed level 1, 6.048 cells/s) and the normal shell to 16 cells/s. On the device the owner found both movement and shells too fast. A first step (R5.1) slowed everything by 20 %; after trying it the owner asked for another 50 %. GAME_RULES §17 item 4 had marked these values for exactly this playtest check.

## Decision

1. One factor applies to every tank and shell speed, so the tank-to-shell ratio (dodging and interception feel) is unchanged. It is now k = 0.4 of R5 (0.8 × 0.5).
2. Player base speed is 1 966 080 mSU/s (1.92 cells/s; 2.42 cells/s at the starting level). Enemies share the base.
3. Shell initial speeds and speed caps are ×k, accelerations ×k² and lifetimes ÷k (rounded), taken from three-decimal cell values, so the unobstructed ranges stay those of R5 within 0.15 cell. Normal 6 553 600 / −187 392 / 270 ticks; rapid 9 362 432 / −280 576 / 412; fire 6 553 600 / −562 176 / 180; AP 2 340 864 / +2 808 832 / cap 7 021 568 / 412; explosion 3 744 768 / +2 996 224 / cap 7 489 536 / 412.
4. AP, explosion and fire in-flight caps are unchanged.
5. The normal round's cooldown follows the same time scale (÷k: 35/30/25/20 ticks, was 14/12/10/8), so consecutive normal rounds sit as far apart on the field as in R5 (about 3.7 cells at LV0) and its in-flight caps are R5's 8/9/11/14 again (R5.3). Players and enemies share the weapon.
6. The rapid cooldown follows the same time scale too (÷k rounded: 20/18/15/13 ticks, was 8/7/6/5), restoring R5's field spacing (about 3 cells at LV0) and R5's in-flight caps 24/28/32/36 (R5.6); rapid still fires faster than normal.
7. Other cooldowns, fire-patch life, spawn and protection timers, and distances such as the ice slide are unchanged.
8. AP C moves at speed level −2 instead of −4: 0.576 cells/s, double, the same as explosion C, about 95 seconds across the arena (R5.8). AP A (0.288), AP B and AP D (0.415) are unchanged, so AP C now outpaces the heavier AP D.

## Alternatives considered

- Lower speeds but keep lifetimes: rejected, every range would shrink with the speed (the fire shell would land far closer), changing the spatial design the stages and rules rely on.
- Slow tanks only: rejected, the owner named both, and shells would become relatively faster, harder to dodge.

## Gameplay consequences

The whole game plays at a much calmer tempo with the same map-scale distances; shells take longer to arrive, so interception and dodging windows grow. Normal fire is sparser: at most about 1.7 rounds a second at LV0, so taps faster than that fall outside the 10-tick buffer and click dry. The slowest enemy (AP A, 0.288 cells/s) needs about three minutes to cross the arena, a §17 watch item; AP C was doubled after the owner saw it crawl.

## Architecture consequences

None: data values in `MovementRuleset.provisional` and `WeaponRuleset.provisional` only.

## Migration cost

Recordings embed their rulesets, but later decisions in this family changed the simulation itself, so recordings older than format 11 are refused rather than replayed (see ADR-0020 and ADR-0021); the M1 movement golden is regenerated (player speed) with a review note. The AP C speed lives in the archetype table, not in a recorded ruleset, so R5.8 bumps the replay format to 11.

## Tests affected

Speed-dependent expectations now derive from the provisional rulesets where practical; long AI approach tests got longer tick budgets; the M1 golden.
