# ADR-0018: GAME_RULES R5 Is the Single Gameplay Authority

Status: Accepted (owner instruction of 2026-09-15: review `sparktread-final-rules-review.md`, settle disagreements with the Astra agent, then treat the agreed document as authoritative and bring the other documents and the code in line with it)  
Date: 2026-09-15  
Related findings / supersessions: supersedes in part ADR-0004, ADR-0010, ADR-0012, ADR-0015, ADR-0016, ADR-0017; the previous `GAME_RULES.md` (research compendium, last at commit 4f2705e) and `PROJECT_MASTER_SUMMARY_ZH.md` are retired

## Context

Gameplay rules were spread across `GAME_RULES.md` (reference research plus a §18 deviation list), `PROJECT_MASTER_SUMMARY_ZH.md` (an older overview still describing a 48×27 arena, five special weapons including Mine and four equipment items), `PRODUCT_IMPLEMENTATION_PLAN.md` §6–§12, and several ADRs. They disagreed with each other and with the code. The owner and Astra then wrote a consolidated review draft (RC4). On 2026-09-15 Claude and Astra (Codex) cross-reviewed it in three rounds plus two verification passes and reached full agreement on a closed, deterministic rule set (R5).

## Decision

1. `GAME_RULES.md` (R5) is the single gameplay rulebook. On any gameplay conflict it wins over the implementation plan, other ADRs, code comments, and research notes.
2. `PRODUCT_IMPLEMENTATION_PLAN.md` stays authoritative for architecture, process, content format, save/replay format, testing and milestones; its gameplay sections are reduced to pointers into `GAME_RULES.md`.
3. The following earlier decisions are superseded where they conflict with R5:
   - ADR-0004 item "the gameplay arena MAY render beneath system UI overlays": the playable map, base, spawn points and projectiles MUST now stay inside the system safe rectangle (R5 §15.1).
   - ADR-0010: the depleted special channel falls back to the normal round on a **press edge**, not while held (R5 §5.1); the fort ring is replaced by an explicitly authored fort template whose full per-quadrant state is recorded and restored with deferral (R5 §11.2); hidden treasures reveal when all 16 quadrants of their 2×2 area are clear (R5 §10.2); mine visibility is moot because mines are removed.
   - ADR-0012: MaxHits and MaxCombos are shown with the exact definitions of R5 §13 (the owner's newer RC4 draft reinstated them); the eight results categories are remapped to the five R5 families (R5 §9.1, §13). Clear-bonus brackets stand.
   - ADR-0015: the mine-laying percent is removed from difficulty profiles; enemy spawning follows the R5 §9.3 cadence (45-tick spawn process, 45-tick no-fire protection, at most one new spawn process per 30 ticks after the first wave).
   - ADR-0016: mine launch and flight are removed; ice slide keeps its 1.5-cell budget but saves the slide speed, ends when the centre leaves ice, and turns the facing immediately (R5 §4.3); losing AmphiTank in water uses the monotone water-overlap exit rule (R5 §4.4).
   - ADR-0017: foliage fire uses the R5 §7.4 once-per-cell spread and last-flame burn-out; the Training Arena order is the fixed R5 §1 order. The no-danger-telegraph rule stands.
4. The shipping content scope is five weapon families (normal, rapid, fire, AP, explosion), two equipment items (AmphiTank, AntiSkid), twenty enemy types and twenty-two pickups. The Mine weapon, the four mine-family enemies, Shield of Moon, Memory of Sea and their pickups are removed.

## Alternatives considered

- Keep `GAME_RULES.md` as research and add R5 as a second file: rejected, it recreates the conflicting-document problem the owner asked to remove.
- Delete the implementation plan: rejected, its architecture, content-format and testing contracts are still the working agreements the code relies on.

## Gameplay consequences

Many: projectile motion and ranges, player speed, wall strips, AP stopping, explosion occlusion, projectile clashes, fire delivery and burning, the base taking one point per hit, Bomb clearing enemies, pickup size and placement, enemy spawn pacing, and results statistics all change as specified in R5.

## Architecture consequences

GameCore gains layered terrain cells (surface under walls and foliage), milli-subunit projectile and tank speeds, a normal-fire input buffer, fire patches keyed by source, per-victim burn cadence, per-cell ignition state, an explicit fort template with pending restores, a pending-pickup queue, and water-exit state. Mines and mine launch are deleted from state, events and presentation.

## Migration cost

Replay format and the M1 movement golden change (player base speed and the rules version); suspended sessions from earlier builds are rejected as incompatible. Stage JSON loses mine enemies and removed equipment, and gains fort templates.

## Tests affected

Combat, combat-contract, movement, traversal/inertia, foliage-fire, stage, navigation, training-arena, stage-content and replay-golden suites; mine-launch tests are deleted.
