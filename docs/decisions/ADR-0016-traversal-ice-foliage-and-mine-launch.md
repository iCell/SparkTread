# ADR-0016: Traversal Profiles, Ice Inertia, Foliage Cover and Mine Launch

Status: Proposed (drafted 2026-09-10 late evening, M4 item 5 — the mechanics M3 deferred)

Date: 2026-09-10

Related: plan §7.3, §7.5, §8.5–8.6, §10.4, §11.2, §12.3, §13.3, §15.3, §18.1, §24 Q8; ADR-0002, ADR-0003, ADR-0010 (mine cloaking, ring restore); `docs/CURRENT_REVIEW.md` "Deferred to M4"

## Context

The terrain table (§7.3) and equipment rules (§7.5, §8.6) name four
mechanics M3 left inert: water blocks tanks unless AmphiTank; ice "adds
inertia/turning friction unless AntiSkid" (no numbers anywhere in the
plan); foliage "occludes tanks/projectiles visually" without hiding
lethal information (§11.2) while mine level/ownership must stay readable
(§12.3); and the §8.6 launch/flight contract (displacement along the
travel direction, an `airborne` status suspended from all interactions,
landing by deterministic ring scan, slow effects, Memory of Sea exempt,
a ruleset/stage switch) whose values are "PROVISIONAL ruleset data". The
turn-buffer and slide fields have been authoritative since M1.

## Decision

1. **Traversal profiles.** `TraversalProfile` (normal / amphibious /
   traction) derives from `equipmentID`; `TerrainKind.blocksTank(profile:)`
   and `TerrainGrid.blocksTank(…, profile:)` make water passable for
   AmphiTank only. `Simulation.ObstacleField` carries the moving tank's
   profile so the swept movement, probes and the AI's local steering
   share it; `Navigation` takes the profile beside `canDig`, so an
   amphibious enemy's cost field crosses water and a normal one's routes
   around it (§7.5: same rules for AI and players). A tank that loses
   AmphiTank with its footprint over water keeps the amphibious profile
   until it is clear — it may leave, never re-enter. The validator's
   reachability flood keeps treating water as solid (conservative for
   every profile); the §15.3 per-archetype waiver is not added.
2. **Ice inertia (numbers provisional).** `MovementRuleset.
   iceSlideDistanceSubunits` (1536 = 1.5 cells; 0 disables). While a
   tank's centre cell is ice and its profile is not traction,
   `slideDirection` remembers its last travel direction; releasing input
   or changing direction there starts a slide of that distance along the
   remembered direction at the tank's normal per-tick speed. During a
   slide, input only turns the facing ("turning friction"), except the
   slide direction itself, which cancels the slide and drives on; a
   block ends the slide flush against the obstacle; leaving ice ends it;
   AntiSkid never slides. Enemies slide by the same rule. Slide state is
   authoritative (it already was) and the M1 movement golden was
   regenerated with a review note (its script crosses the lab's ice
   patch).
3. **Foliage cover (presentation only).** The scene draws foliage cells
   from the 47-joint atlas (three frames) at z 520 — above tanks (500),
   below mines (600) and projectiles (650), so ordnance stays readable
   (§12.3) while tanks are concealed; cells over the player's footprint
   fade to 45 % (vendor guidance: local fade) so the player never
   disappears. Plan §24 Q8 (AI perception) stays open — the brain does
   not see foliage; flammability stays off.
4. **Mine launch/flight (numbers provisional, `WeaponRuleset`).** Per
   mine level: launch distance [0, 1024, 1536, 2048] subunits, airborne
   ticks [0, 18, 24, 30], slow ticks [0, 60, 90, 120];
   `mineLaunchEnabled`; `MovementRuleset.slowedSpeedPercent` 50. After
   the blast resolves, the triggering tank — alive, not already airborne,
   not carrying Memory of Sea; protected tanks included — is thrown
   along its movement intent (else facing) by the level's distance
   (clamped to the arena), gets `airborne` for the level's ticks with
   `TankState.landingSubunits` (new authoritative field: checksummed,
   invariant-bound, decodes as nil), and `slowed` for airborne + slow
   ticks (one status; it has no effect while airborne). While airborne
   the tank does not move, turn, fire, trigger mines, collect pickups,
   take projectile/blast/flame damage, block other tanks or count as an
   AI target. When the status expires (step 2) it lands at the nearest
   legal footprint to the nominal point by `RingScan` (radius 4; terrain,
   tanks and the base; in place when none is free) and its accumulator
   resets; only the triggering tank flies; friendly mines still never
   trigger.
5. **Replay format 6**; the rulesets decode older shapes with the
   defaults (the format gate separates them anyway).

## Consequences

- Movement and combat tests: profile/water crossing, the water-leave
  case, navigation profiles, slides (release, direction change, cancel,
  wall, leaving ice, AntiSkid, disabled, serialization), launches
  (distance/direction/flight/landing/slow, untargetable/non-blocking,
  landing fallback, exemptions and the switch, destroyed-tank case,
  serialization), foliage presentation (z, joints, fade, removal).
- VS-02's water channels and foliage cover now play as authored;
  AmphiTank/AntiSkid pickups have mechanical meaning.
- Open for the owner: every number above; whether protected tanks
  should fly (implemented: yes, Memory of Sea is the only exemption);
  whether enemies in the blast radius other than the trigger should fly;
  foliage AI perception (§24 Q8); flammability; a wake/skid decal and a
  landing effect (assets exist: `amphiWake`, `skidTrail`).
