# Current implementation review

Date: 2026-09-09. Two independent agents (PI: gpt-6-astra, Claude: Fable
5.1) cross-reviewed the tree in seven written rounds; PI verified findings
with compiled check programs, Claude applied every change both agreed on.
This document is the state after that pass (seven rounds, closed in round
7). It is not a claim of product completion, physical-device acceptance, or
audio-content acceptance.

## Scope and authority

This began as a one-stage development prototype (VS-01); the campaign has
carried all twelve V1 stages since 2026-10-03.
`GAME_RULES.md` (R5, ADR-0018) wins every gameplay conflict; accepted ADRs
override the product plan; reference-game behavior and older SVG/styleboard
assets do not override those decisions. Runtime art is the
`Vendor/SparkTreadPixel` submodule; no new artwork was generated.
ADR-0010 has since been accepted and is partly superseded by ADR-0018.

## Corrections made in the joint review

Core (GameCore):

- Projectile contacts of a tick resolve from one global time-ordered queue
  (world contacts and projectile-versus-projectile, exact rational times,
  category/ID tie order). Crossing shots that pass at different times no
  longer cancel; an interception earlier in the tick prevents a later base
  hit in the same tick. Blasts still resolve after the queue (documented
  approximation in `Combat`).
- Negative-direction shots (left/up) meet walls at the same distance as
  their mirrors (entered-quadrant sampling).
- Penetrating shells (AP) damage each distinct tank once
  (`ProjectileState.hitTankIDs`) and keep their remaining travel; surviving
  contacts emit `projectileHit`, never a false destruction; mines disarmed
  by shots emit `mineRemoved`.
- Enemy flame patches release their active-count slot on the emitter
  (`FireHazardState.ownerEntityID`); expiry by lifetime releases slots;
  flame volleys are admitted whole or refused (dry-fire + cooldown);
  active counts are checked for exact equality by `WorldInvariants`.
- Every dry-fire path applies the channel cooldown (held special against an
  illegal placement dry-fires at cadence, not per tick).
- Protection policy centralized: spawn protection and invincibility deflect
  projectiles, blasts, flames and the bomb alike; dead tanks and a base at
  zero take nothing and emit nothing.
- Flames burn the base: one contact patch per column on the structure,
  once per fire-damage interval, through the ADR-0005 allied flag and the
  shield; the column stops at the base.
- Fort ring (base shield): occupied cells (tank/mine/pickup) are never
  rebuilt — no entombment; damaged steel hardens whole; expiry restores from
  a per-activation record (`BaseState.fortRingRestore`; steel/water
  preservation via `PickupRuleset.fortRingRestoresRecordedKinds`, default
  on since the owner's decision B of 2026-09-10; off = rebuild as brick).
- Hidden treasures reveal only when the covering cell can hold a pickup;
  the record survives a failed placement.
- Score pickups award points; `max_armor_ammo` fills the current special to
  its cap (distinct from `ammo_crate`).
- `PickupRuleset` (lifetime, grace, armor-up, invincibility floor/refresh/
  extend, base shield extend/floor, freeze, bomb damage) replaces hard-coded
  constants with identical tuning constants; validated at the loading
  boundary (`StageLoader`) and by sessions; timer sums saturate. One
  behavioural difference is deliberate and documented on the rule: a
  longer running invincibility timer is no longer shortened to 600 ticks by
  a pickup. The reference 25-second rule is available as
  `.referenceInvincibility`, NOT applied.
- Domain events carry owner identity, positions (anchors documented on
  `DomainEvent`), facing, and structured impact kinds; `baseDamaged.allied`
  distinguishes own fire (ADR-0005).

Application / adapters:

- `ReplayRecording` v2 embeds the initial world and all three rulesets;
  playback validates, before stepping: format; every embedded ruleset
  (`MovementRuleset`, `WeaponRuleset`, `PickupRuleset`) against documented
  value domains, each field range-checked before the arithmetic that
  depends on it; the world's structure (bounded arena, matching terrain
  storage) and invariants (positions inside the arena, timers/counts/armor
  inside their domains, signed bounds compared directly, incremented
  counters admitted with headroom);
  the start checksum; command envelopes (none before the initial tick, no
  duplicate tick — envelopes are mapped by tick, chronological storage is
  not required); the tick count (0…10 h) and its sum with the initial tick.
  Invalid data within those checks is a `ReplayError`; the maintained tests
  cover emptied weapon arrays, invalid pickup rules, negative initial tick,
  mismatched terrain storage, duplicate envelopes, extreme integers in the
  movement inset, a tank position, the projectile extent, the arena size,
  Int.min slide momentum, Int.max spawn cursors / telegraph index / tick /
  next entity id. Debug mutations rebase the recording. A VS-01 session started at a
  nonzero tick replays through encode/decode.
- `TickAccumulator` (ADR-0007): raw gaps longer than six ticks (with a
  floating-point tolerance valid at any uptime) are dropped as stalls
  (implicit pause, no burst); fractional remainders carry; duplicate,
  backward and non-finite timestamps never move the accepted baseline.
- Application lifecycle: `MovementLabController.start/suspend/stop` driven
  by `scenePhase`; a controller is constructed INACTIVE (audio and haptics
  suspended, input refused) until the view reports the active phase;
  suspension is a complete barrier — audio and haptics suspended, held
  inputs released, new presses refused, queued presentation events
  discarded; `start` advances the input reset watermark so a physical
  callback observed while inactive is dropped even when delivered after
  resume; bottom system gestures deferred (ADR-0004).
- Input: `HeldDirectionStore` accounts per source — each key, each CONTROL
  of each controller (object identity, not an enumeration index), touch —
  for directions AND fire (normal edge per source, special hold); key repeat
  keeps its priority slot; keyboard J/U normal, K/I special (reference
  defaults, provisional); controller A / B / X; a disconnect releases only
  that device (held inputs and its pending pulse) and invalidates the
  callbacks it queued (`DeviceGenerations`); a restart/suspension reset
  drops earlier callbacks globally.
- Audio structure: injectable backend and monotonic clock; suspend/resume/
  mute lifecycle (a new world stops one-shots too); wanted loops are
  reconciled against actual playback with a one-second retry backoff;
  exact impact voices from event payloads; player-only, throttled dry fire
  whose throttle commits only when a click actually played; base-hit
  priority per drained batch; allied own-fire voice (`sfx_base_own_hit`,
  provisional placeholder). Sound CONTENT was replaced on 2026-09-10 by the
  candidate reference-derived set — see "Reference audio and transitions".
- Presentation: impact/pickup/shield/spawn effects from event payloads;
  muzzle flashes anchored to the event's footprint and facing (the live rig
  contributes only its muzzle offset); the ADR-0005 own-fire base cue is an
  adapter-owned tinted silhouette overlay (teal for allied, red for enemy)
  — an SKAction on the vendor base node would not tint its private sprites;
  spawn-protection ring, invincibility ring, freeze overlay, equipment
  attachments; mines through `PixelMineNode` (badge, level, arming); pickup
  expiry blink; base shield appearing/warning phases; bounded effect and
  scorch pools; `PixelArt` retained across restarts; explicit surface
  change; ground strip clipped to the arena; liquids reconciled through
  terrain changes (water → steel → water).
- Debug overlay, collision box and the weapon cheat panel exist only in lab
  mode (`MOVEMENT_LAB=1`); the playable stage shows a provisional HUD with
  lives, armor, weapon/ammo, power/speed, equipment, status, enemies, base
  and score.

## Validation evidence (latest tree, 2026-09-10)

Recorded separately from the 2026-09-09 evidence below, which describes
the tree as it was then and is not rerun here. After the owner's
decisions of 2026-09-10 evening and the ADR-0012 results/bonus work:
`Scripts/ci.sh` passes end to end (Claude's run; PI was unavailable) —
architecture check, content validator, `Scripts/check-audio.sh` selftest
and check (18 synthesized files match the generator, 8 excerpts match the
manifest and the re-run extractor), `swift test` 329 tests / 82 suites (after M4 items 1–5, the arena, ADR-0017 and the follow-ups),
xcodegen, the simulator `xcodebuild test` on iPhone 17, the smoke render
selftest and the smoke render itself; `git diff --check` is clean. This
paragraph is the one current count; the handoff repeats it with the same
date.

## Validation evidence (2026-09-09)

- `swift test`: 193 tests / 45 suites at the round-7 closure (Claude;
  PI's independent run matched), 204 / 48 after the same-day
  owner-directed changes (round 8). Historical counts; the current one is
  in the section above.
- `xcodebuild test … 'platform=iOS Simulator,name=iPhone 17'`: succeeded
  (run by Claude after batch 3, after the round-4 fixes, and after the
  round-5 fixes; PI did not run the simulator gate).
- `sh Scripts/check-architecture.sh`: passed. `swift run content-validator
  Content`: passed. `git diff --check`: clean.
- Audio regeneration is deterministic (at the time: every existing WAV
  byte-identical by sha256, only `sfx_base_own_hit.wav` new). The
  2026-09-10 candidate set replaced most voices; PI regenerated that set
  twice outside the repository and matched all 28 files.
- The M1 movement golden was regenerated once with a stated reason: the
  checksum surface gained `BaseState` fields; the run fires no shot.

## Reference audio and transitions (owner direction 2026-09-09/10; ADR-0011 proposed)

The owner wants the reference game's (决战坦克) sound effects and transitions
replicated and supplied a complete gameplay recording (public video, 32
stages, ~50 min). Policy (plan §12.7, manifest §M): extracted reference
audio is research-only until the owner records a rights decision, and
RE-SYNTHESIS IS A CANDIDATE PRODUCTION METHOD, NOT CLEARANCE — the
candidate set in the working tree (`Tools/build_audio_assets.py`, rendered
at 8363 Hz with zero-order-hold upsampling as an audition hypothesis) is
provisional until the owner's audition and a recorded provenance/rights
review. Nothing extracted is in the repository. The research clips,
spectrograms and scripts were LOST with the machine restart of 2026-09-10
(≈10:17); what follows are Claude's reported measurements, not
independently re-verified by PI. The reproducible record is
`Tools/reference_measure/` (README with source id, timebase check, the
per-sound and per-transition windows, and the scripts; no media): rerunning
it on the public recording regenerates every number below.

Attribution status: CONFIRMED against frames — enemy destroyed (rumble),
pickup collected (arpeggio). UNCERTAIN — the glide taken as the shot, the
burst taken as the engine (and the engine's trigger: bursts while the
player stood still at 17.9 s, silence while an enemy kept moving at 52 s).
DERIVED — every other voice (launch variants, heavy explosion, base
collapse, pickup appearance, steel/brick/deflect, tally tick, stage card,
win stinger); INVENTED — the loss stinger (no loss in the recording;
removed 2026-09-10 late evening: the owner wants the reference passage at
every stage end).
Native-rate hypothesis: two mirror pairs sum to 8377 and 8355 Hz; a third
pair quoted earlier (2692 ↔ 5017 = 7709 Hz) does not fit and is withdrawn.
Per-file peak normalisation makes the envelope points relative shapes, not
calibrated dBFS.

Measured (STFT, 2.5–5 ms hops; times are positions in the recording):

| Sound | Where | Measurement → synthesis |
| --- | --- | --- |
| shot (assumed: the most frequent tonal event, runs at 0.2 s) | 43.17 s ×8, 87.8, 89.1, 90.2 s | pulse wave, exponential glide 3.1 kHz → 0.5 kHz, ≈0.26 s, flat then 30 ms release |
| engine burst (assumed: held direction) | 17.9–19.3 s, 47–52 s | 300 ms noise, broad, peak 2–2.5 kHz, roll-off above 3 kHz, V-chirp 2.3→3.0→2.2 kHz in the last 120 ms; 0.3 s on / 0.1 s off |
| enemy destroyed (confirmed: kill + score roll at 21.87 s) | 21.9 s, 63–67 s | 0.2 s low crunch (≤900 Hz) then a 260→170 Hz tone, −13 dBFS for 0.3 s, −40 dB by 0.7 s |
| heavy explosion (kill at 98.62 s) | 98.6, 100.3, 103.5 s | 0.2 s hiss (tread spectrum) then 0.6 s rumble ≤350 Hz |
| pickup collected (confirmed: score +2000 at 104.76 s; "Flag On Guard!" at 38.12 s) | 38.12, 104.76, 105.52 s | triangle notes C6 110 ms, C5 70, G6 30, C6 30, G5 90, C5 20, G6 30, E5 30, G5 70, C5 20, G6 20, C6 70, G5 20, C5 40; envelope −2 dB → −40 dB over 650 ms |
| steel click | 102.28 s | 2.69 kHz tone, 130 ms, −6 → −20 dB by 100 ms, over a 40 ms 150 Hz thump |
| tally blips | 77.4–77.7 s | 3.14 kHz and 1.85 kHz blips during the results table |
| stage card slide | 79.2–79.8 s | 1.2 → 0.86 kHz tonal slide under the title |
| results drum riff (reacquired audio; owner: "dong ×6, dong ×6, dong, dong ×4") | 73.9–78.3 s | ≈37 low-band hits (`hits.py`) in groups of 5–7, ≈0.12 s between hits, ≈0.24 s between group onsets; one hit: body ≈150–195 Hz, broadband stroke, −10 dB by ≈120 ms (0–250 Hz 0 dB, 250–500 −6, ≈−16 flat above 500 Hz). The first cut read this as an amplitude-modulated bed — wrong |
| stage-card drum riff (reacquired audio) | 78.3–79.6 s | the same riff (8 hits, rest, 2, rest, 1 …) until play; the first card (8.54–9.13 s) opens with six hits |

Transitions (frame-accurate, seeks verified against the audio):

- Intro: card 8.9 s; title slides in from the left 9.4–10.4 s and holds;
  cross-shaped strip reveal of the playfield 11.2–11.6 s; title flips away
  11.6–12.0 s; HUD and player spawn at 12.0 s.
- Outro: last sound 70.8 s; "Mission Complete" appears at the centre
  72.73 s and rises to the top by 73.07 s; playfield darkens 75.5–76.0 s;
  the results table (kills by enemy type, total, reward) slides in from the
  left 76.0–76.5 s and counts up with ticks; next stage card 78.27 s;
  reveal 79.5 s; play 80.0 s. The video has no loss, so the loss variant
  (same motion, restart button) is ours.

Implemented (2026-09-10): `StageFlow` (GameApplication, pure tick
timeline gating the simulation, cues for sounds; results capacity derived
from the tally, hold stretched to fit), `KillTally` (results rows from
events), the scene's per-cell curtain lifted in growing-cross order,
SwiftUI card/outcome/fade/panel animations with the measured durations
(touch controls hidden over the card and the results), the candidate set and its
mapping (`GameAudio.soundNames`); outcome stingers moved from the decisive
event to the transition. Round-11 corrections (PI): transient effects age
on the scene's presentation clock so the decisive tick's explosion plays
out during the outro; ONE input-admission policy (clock running AND flow in
play; every transition releases held/pending input and advances the reset
watermark, so cutscene presses never reach the first gameplay tick); the
completed recording is kept on the controller before the automatic
continue. Not implemented: the reference's stage-clear "Reward" bonus (a
scoring rule; owner decision), tank icons in the results rows, a title
screen. The automatic continue replays the same stage (provisional
prototype loop, not campaign progression).

Owner's CREATIVE decision of 2026-09-10 (later the same day, verbatim; not
a rights decision — the distribution-rights review stays PENDING for the
excerpts and the synthesized voices alike, `ASSET_PRODUCTION_MANIFEST.md`): "我不是让你重做，是让你采用
决战坦克原版的开场音效，我要求音效是复刻原版的" — the sounds are to be the ORIGINAL
game's sounds. Applied: `Tools/extract_reference_audio.py` extracts the
cleanest isolated instances from the pinned recording (isolation score:
silent margins), deterministically resampled; eight files are now
EXCERPTS of the recording (processed cuts, not the game's asset files) — `sfx_stage_win` (end-of-stage loop
74.00–78.20 s, the results screen from its rise to the card; the owner
identified it as the end sound), `sfx_fire_normal`/`_rapid`/`_special` (the one isolated
shot instance at 185.29 s; whether the reference has other launch sounds
is not established), `sfx_tank_explode`
(21.86 s), `sfx_player_explode` (heavy, 100.20 s), `sfx_pickup_collect`
(104.74 s), `sfx_hit_steel` (click, 102.26 s). The manifest marks them
`excerpt` with window, processing, file hash and the extractor's hash; `Scripts/check-audio.sh`
verifies hashes and re-extracts when `SPARKTREAD_REFERENCE_WAV` is set.
Cue table for the audition (source vs. attribution confidence are
separate columns):

| Cue | Source | Event assignment | Audition |
| --- | --- | --- | --- |
| stage card | ORIGINAL composition (`inspired`): NES-style jingle following Battle City's stage start (Namco) in key, tempo, rhythmic skeleton, instrumentation and length — own melody; no excerpt, not a transcription | owner chose this over a near-copy | ACCEPTED by the owner 2026-09-10 ("开场曲子我觉得可以") |
| stage won | excerpt (end-of-stage loop 74.00–78.20 s) | the results-screen loop the owner identified as the end sound | ACCEPTED by the owner 2026-09-10 ("结束曲还是用决战坦克的那个"); rights review pending |
| normal / rapid / special launch | excerpt (shot 185.29 s, one clip, three names) | glide = shot: assumed, uncontradicted | pending |
| enemy destroyed | excerpt (21.86 s) | confirmed (score roll) | pending |
| player destroyed | excerpt (heavy explosion 100.20 s) | assigned by sound design | pending |
| pickup collected | excerpt (104.74 s) | confirmed (score +2000) | pending |
| steel / boundary | excerpt (click 102.26 s) | assigned; cause not observed | pending |
| everything else | synthesized, provisional | derived / invented | pending |

Still synthesized (no isolated instance in the recording): brick hit,
deflect, pickup appear, tally tick, stage lose, base hit/own-hit/collapse/
shield, ap/explosion/flame/mine launches, flame loop, spawn warp, dry
fire, hit tank, explosion blast. The re-synthesized riff of the same day
is superseded.

Owner's opening-sound correction (2026-09-10, later still): the opening
reference is the first seven seconds of the NES Battle City sound-effects
video (Namco's stage-start jingle, 2.63–7.2 s of that video: two pulse
voices, triangle bass, noise drums on a 0.15 s grid, ≈100 bpm, 4.6 s), and
the owner asked whether it can be used without the copyright problem.
Recorded answer: it is Namco's composition and recording; an excerpt or a
note-for-note re-creation would reproduce it. Applied: `sfx_stage_card` is
an ORIGINAL NES-style jingle (generated, attribution `inspired` with the
second reference on its manifest entry). The owner then asked for a
near-copy of the melody with slight changes; Claude declined (slight
changes do not avoid copyright) and offered three paths; the owner chose
to keep the original and follow the reference's direction as far as
possible — the jingle now shares the reference's key/mode (C minor),
tempo (≈103 bpm), rhythmic skeleton, register, instrumentation and length
(≈4.66 s) with its own note sequences and contours (no note run of the
reference reproduced), no Battle City audio in the repository, the
provisional 决战坦克 card excerpt withdrawn (eight excerpts remain). Not a
legal clearance; the rights review for the whole set stays pending.

Earlier owner decisions after the device session (2026-09-10, applied): NO
engine/tread sound (voice, retrigger and tests removed; the attribution
question is moot); a LONGER sound on entering and on finishing a stage,
like the reference — `sfx_stage_card` is the 6-6-1-4 drum riff
(≈2.6 s; the owner corrected the first cut's throbbing bed the same day:
"开场音效错了", then sang the pattern) and `sfx_stage_win` the riff twice
(≈5.2 s) through the results, both from the reacquired recording's hit
measurements above and played at the card cue and at the outcome text;
`sfx_stage_lose` was an invented slower, falling variant (removed later
that day on the owner's instruction). The owner also
reported the tank's movement stuttering while firing rapid rounds: three
mitigations landed — the simulation driver's PREFERRED callback rate
is the tick rate (60 Hz; a preference, not a guarantee, and SpriteKit
renders on its own schedule — the hypothesis is that a 120 Hz callback
cadence alternated 0/1 ticks and turned into 0,1,1 under load), audio
voice pools are warmed at construction and playback never allocates or
restarts a playing voice (a short or busy pool drops the launch), and
own-recoil haptics are throttled to one impact per 0.12 s
(`RapidFireAudioTests`, `RecoilThrottleTests`). These are PLAUSIBLE
main-thread costs at twelve shots a second, not a profiled cause: the
symptom is undiagnosed until the owner's next device session compares
sustained movement with and without rapid fire (frame intervals and ticks
per rendered frame); if it persists, profile the per-hit effect-node
construction and `syncProjectiles`. Cue timing is adapted: the results bed
starts 0.45 s after the outcome text, the reference's about a second after
its text (historical pairing). The bed's band spectrum was tuned against
the reference bed with `bands.py` (a rough comparison: up to about 4 dB
off in one 250 Hz band, 0–4 kHz; PI reproduced the vector).

Owner check still open: is the synthesized set close enough — and in
either case the provenance/rights review has to be recorded before the
set is shipped.

## Owner-directed changes after the first device session (2026-09-09, after round 7)

Applied by Claude on the owner's feedback from the iPhone 17 Pro; PI
re-verified them in rounds 8–9 (R8-01 goal-cost convention, R8-02 fallback
placement legality, R8-03 replay boundary — all closed; see "Joint review
status"):

- Drops (carrier items and kill rolls) appear at a random interior cell
  anywhere on the map, never under the base or a tank — the fallback around
  the death cell keeps the same constraints, and an item with no legal cell
  anywhere near is lost rather than placed under a tank (`PickupRuleset.
  dropsSpawnAtRandomCells`, default true; ADR-0010 item 7, proposed).
  `spawnPickup` now excludes the base box for every placement.
- Enemy navigation (§10.4): a deterministic cost field over footprint
  anchors (`Navigation`), Dijkstra from the target — the four aligned
  firing positions beside the base (corner cells only as a fallback) or the
  player's neighbourhood — with steel/water/base impassable and brick
  passable at a cost for families whose weapon breaks brick (flame routes
  around it); the cost convention prices the goal cell too, so a cheap
  clear approach beats digging into an expensive one. At a goal the enemy
  faces the target and holds; the free-direction probe is snap-aware like
  the movement system, so a tank a few subunits off a dug opening still
  takes it. Base focus raised (normal 80 %, rapid 50 %, AP/explosion 90 %).
  Tests: field shape, mixed-cost goals, flame routing around brick, an
  enemy crosses the open arena and digs through a brick band to the fort
  (base shielded, approach only), an unobstructed enemy actually damages
  the base, and the first VS-01 wave reaches the fort ring within a minute.
  Observed in the fixtures: an enemy aligned with an unshielded base fires
  along the row and can destroy it from thirty cells away — reference
  behaviour, worth a device look.
- Replay format is now 3: earlier recordings embed a rules shape and an
  AI this build no longer reproduces and are rejected as
  `unsupportedFormat` at the DECODING boundary (header-first check, so a
  real format-2 file never surfaces as a key-not-found error). Policy, not
  an enforced build identity: a behaviour-changing simulation change must
  bump the number; an un-bumped one is undetectable except as a checksum
  mismatch (R8-03 / R9 closeout).

## Joint review status

Closed in round 7 (2026-09-09): PI independently re-verified every item it
had raised (R3-01…05, R4-01…06, R5-01…04, R6-01/02) against the current
tree with its own check programs and package test run, and reported no
further implementation correction in this scoped pass. Rounds 8–9
(2026-09-10) covered the owner-directed drops/navigation changes and the
replay boundary: R8-01/02 closed by PI's exact reproducers, R8-03 accepted
with the header-first decoding correction applied. Round 11 (reference
set + transitions) returned five findings — R11-01 outro effect clock,
R11-02 cutscene input leak, R11-03 engine attribution policy, R11-04
provenance/evidence wording, R11-05 results capacity — all applied with
integration tests (`StageFlowIntegrationTests`, 15 tests driving the
controller callback, the scene drain and the audio backend). Round 12: PI
closed R11-02…05 with its own reproducers and raised R12-01 (the scene's
presentation clock kept aging effects through a controller suspension) —
applied: `MovementLabScene.update` ages nothing while the controller is
not running and rebases on the first active frame, the SCENE is paused
while the scene phase is inactive (parking SKActions), two regressions
use the production update loop. The first cut passed `isPaused:` to the
`SpriteView` itself; that left the SKView blank on device and simulator
(owner report of 2026-09-10: flat gray after the intro, reproduced in the
simulator in the lab world too) and was replaced the same day. PI verified
the replacement on a separate, freshly created simulator (stage card,
post-intro playfield, lab, and rendering again after Settings and back) —
simulator evidence, not device acceptance. `Scripts/smoke-render.sh`
(in CI, needs ffmpeg) now cold-launches the stage and the lab and requires
real luminance spread in the playfield region with a bounded retry; the
HUD cannot serve as the assertion because it kept updating over the blank
SKView. Round 13: PI showed the remaining case — a
suspension with no frame in between still counted the clamped 0.1 s on
resume — fixed with `MovementLabController.activityGeneration`, which the
scene clock compares before computing elapsed time (control-compared
regression at the 0.70 s lifetime boundary with an observable clock
value); two README statements corrected (source sample rate not assumed,
61 ms ≈ two frames, pairing settled only by the alignment check). Round 14
(2026-09-10): PI reran every R11/R12 reproducer against the current
objects (suspended callbacks, no-inactive-frame resume at the 0.70 s
boundary, active-outro expiry, final-intro-tick presses, steel-blocked
engine, nine-archetype results) and recorded the R11/R12 findings as
independently reverified and CLOSED at this scope.

Round 15 (whole-tree pre-commit pass, 2026-09-10) raised nine items; all
applied:
- R15-01 (High) decoded out-of-domain entity ids trapped in AI cadence
  arithmetic → `WorldInvariants` checks every entity id and id reference
  (owners, hit lists) against `1..<nextEntityID`; −1 stays the documented
  no-owner sentinel; `EntityIDDomainTests` cover every entity kind, the
  exact boundary and PI's negative-enemy-id replay reproduction.
- R15-02 (High) a single `Int.max` enemy count passed validation →
  `StageValidator.maxEnemiesPerStage` (500) per entry and in total, timer
  and cap domains from `WorldInvariants`, and `StageBuilder` validates
  before it allocates (`StageBudgetTests`).
- R15-03 (Medium) open-edge worlds moved the nominal footprint outside the
  arena → movement bounds the NOMINAL footprint; the inset applies to
  obstacles only (`ArenaBoundaryTests`, four edges, approach, turn assist).
- R15-04 (Medium) session validated pickups only → all three rulesets are
  preconditioned; `MovementLabSession.make` throws for data
  (`SessionConfigurationTests`).
- R15-05 (Medium) every loss read "基地失守" → the loss reason travels with
  `StageFlow`, titles are truthful (`OutcomeTitleTests`); results rows
  scroll inside a panel bounded to half the surface, restart outside it —
  a layout policy, not device-verified for large tallies.
- R15-06 (Medium) README now states the Foundation exception at the
  content-loading boundary, matching the architecture check.
- R15-07 (Low) handoff consolidated (current counts, candidate status,
  round-14 closure), stale source comments fixed, event-anchor doc attached
  to `DomainEvent`; this document keeps dated evidence sections.
- R15-08 (Low) integration-test time is an explicit input advanced once per
  frame.
- R15-09 (Medium) `Tools/audio_manifest.json` (per-file sha256, length,
  attribution, generator hash, pending shipping review) and
  `Scripts/check-audio.sh` (regenerate outside the tree; compare files and
  manifest), wired into `Scripts/ci.sh`.
PI's suggested commit split (core/content contracts; adapter lifecycle and
presentation; stage orchestration + candidate audio + ADR; tooling + docs)
is recorded in the handoff for the owner. Rounds 16–17 closed R15
(R16-01 results hit testing, R16-02 evidence counts). Rounds 18–19
(owner-directed changes after the device session: no engine sound, longer
stage stingers from the reacquired audio, rapid-fire stutter mitigations):
PI closed R18-01 (playback never allocates), R18-02 (recoil boundary),
R18-03 (hypothesis wording) and requested no further synthesis change
before the owner's audition. Round 20 (owner: blank playfield on the
phone): cause was round 13's `SpriteView(isPaused:)` binding; replaced by
pausing the scene on inactivity; PI verified the replacement on a fresh
simulator; its recommended presentation smoke test is
`Scripts/smoke-render.sh` in CI (round 21). Round 21 (PI): the first
classifier accepted the intro card (contrast alone) and a failed launch
could pass — replaced by a gameplay-surface predicate (≥ 20 % frontier
ground pixels and ≥ 2 % brick pixels in the central crop), strict failure
propagation for launch/capture/classification, a simulator-free
`selftest` (synthetic positive; intro-card, flat and results-overlay
negatives; mock launch and capture failures must fail the gate), and
ffmpeg required under CI (`brew install ffmpeg` in the workflow) while a
local miss still skips with a notice. Round 22 (PI): the decoder's status
was masked by the pipeline and the results negative was whitened instead
of darkened — the crop is now decoded to a file with a checked ffmpeg
status (a decoder that fails after plausible output is rejected; self-
tested with a late-failing wrapper), and the results fixture uses output
maxima plus title/table blocks and is asserted darker than its source
before the classifier must reject it. Round 23: PI reran its decoder
injection and the real smoke on a fresh simulator (stage 61.4 % / 23.6 %,
lab 82.0 % / 10.6 %) and CLOSED rounds 20–22; the guard is a smoke check
for the frontier fixtures, not a general visual test, and
background/foreground automation stays deferred. Engineering review is closed
at every scope reviewed. Round 24 (drum riff): PI accepted the owner's
6-6-1-4 phrasing for the synthesized riff and raised R24-01 (docs still
described the removed bed) and R24-02 (`hits.py` timebase) — R24-02
applied (frame times from hop/rate, detector labelled heuristic); R24-01
is superseded by the owner's originals decision, and the builder's riff
comments were corrected for the one synthesized use left (the loss
stinger). Round 25 (excerpts): PI closed R25-01 (creative decision separated from the
PENDING rights review; "excerpt" terminology), R25-02 (extractor hash and
full excerpt-metadata comparison, self-tested), R25-03 (protected names
refused before any write) and R25-04 (mapping rewritten) in round 26,
which raised R26-01 (metadata wording: provisional endpoint, one
selected launch instance, 15–80 ms fades, the silent-margin exception)
and R26-02 (preserve the rhythm-analysis scripts and windows in the
record) — both applied. The opening-sound excerpt stays PROVISIONAL until
the owner pinpoints it; no further blind re-cut. Round 27 (original jingle): PI accepted `inspired` as a provenance class
(not a legal conclusion), kept the intro duration (the jingle's tail
overlaps ≈1.8 s of play; duck rather than delay control if cues suffer),
and raised R27-01 (the excerpt self-tests mutated the now-generated card)
and R27-02 (comment/README/provenance migration) — both applied: the
self-tests target `sfx_stage_win.wav` after asserting it is an excerpt,
generated entries have their own corruption cases, the card's manifest
entry carries its inspiration provenance, durations are stated as phrase
vs file, and the README's withdrawn windows are marked historical. The standing limits (audition, provenance/rights, device
performance/layout, video re-alignment, ADR acceptance, commit) are the
owner's. Standing limits stay
explicit and pending: owner audition, reconstructed measurement evidence
(a rerun of `Tools/reference_measure/`), provenance/rights review,
large-results-panel layout, device readability/mix/performance, broader
product acceptance. (ADR-0010 and ADR-0011 were accepted by the owner
later on 2026-09-10 — see the decisions below; the review itself never
accepted them on the owner's behalf.) Round 28 (R27-01/02 applied, the
jingle revised toward the reference's direction and accepted by the
owner) reached PI, which began verifying (`check-audio.sh selftest` in
both modes, `git diff --check`) and then hit its ChatGPT usage limit
("Try again in ~7167 min", ≈5 days); the round has no PI reply. The
changes after round 27 (jingle revision, the owner's decisions B/3/4/6/7,
the reward rule) are therefore Claude-only until PI is back. This is a scoped
review sign-off, not a claim that every possible malformed recording is
safe, that the product is complete, or that device/audio acceptance has
passed — see the gaps below.

## Owner decisions of 2026-09-10 (evening)

Recorded verbatim: "应该是 B 恢复为加固前记录的材质；3 正确；4 正确；5，按照原作来；6 消失了；7 提交；9 不用".

- ADR-0010 accepted; fort-ring restoration = B (recorded materials):
  `PickupRuleset.fortRingRestoresRecordedKinds` now defaults to `true`.
- ADR-0011 accepted; the shot attribution (the glide) confirmed.
- Rights: the owner reviewed and accepts the use of the eight recording
  excerpts, the synthesized voices and the original jingle with no
  third-party licence held; recorded in `Tools/audio_manifest.json`
  (`rights_review`) — the decision and its responsibility are the owner's.
- Stage-clear reward: to follow the reference ("按照原作来") — measured
  from the reference's results screens and implemented the same evening
  (ADR-0012, proposed; section below).
- Rapid-fire stutter: gone on the device ("消失了").
- Commit the tree ("提交"); no CLAUDE.md ("不用").
- Invincibility duration: decided later the same evening — A, keep 10 s
  ("保持 10 秒"); the ruleset default stands, the reference's 25 s rule
  stays expressible data.

Second batch, 2026-09-10 late evening (on ADR-0012's questions and the
first device look at the results panel): invincibility "保持 10 秒"; the
bonus bracket rule "我不知道原作怎么算的，你可以用一种最合理的方式来决定" (delegated —
the stage-number brackets stay, see ADR-0012); MaxHits/MaxCombos "不要";
table icons "坦克图标". Two complaints: the results panel "很难看" (the
first cut stretched across the whole landscape surface with the subtotals
far from the counts) and the stage-end music "时好时坏，需要用决战坦克的那个音效"
— a lost stage played the invented falling stinger, a won one the
reference excerpt. Applied: the panel is a compact reference-style card
on the left (title band, "icon count icon count ×k = subtotal" rows with
the tank icons composed from the rig sprites, rule, 总计, the reward text
rising over the title, score and restart in the footer; width 44 % of the
surface, at most 400 pt); the reference's results passage plays at every
stage end and the invented loss stinger is removed from the generator,
the bundle and the manifest (26 files).

## Stage-clear results table and bonuses (owner decision 5, 2026-09-10 evening; ADR-0012 proposed)

Survey (`Tools/reference_measure/results_screens.py`, media-free) of the
first 30 results screens of the owner's recording (the video's last 9 %
would not download; 30 of 32 stages). Read by eye from the crops:

- The table is FOUR rows of two tank icons with kill counts, "×k =" and a
  subtotal (k = 1…4), then "总计" = Σ subtotals; a "MaxHits N / MaxCombos
  N" line sits above. Every screen obeys subtotal = (left + right) × k
  (stage 3: (2+2)×1, (3+0)×2, (2+0)×3, (1+0)×4 → 20). The eight icons are
  the eight §8.2 reward categories in row-major order (rows 1 and 4 pair
  two colour variants of one chassis: the Normal pairs, the AP pairs) —
  inferred from the icons, not from attributing kills in the footage.
- Two constant bonuses per cleared stage, read from the score counter
  before/after the panel and the rising "Reward +N" text: stages 1–10
  tally +200 / reward +330; 11–25 +600 / +660; 26–30 +1000 / +1000.
  Independent of kills, total, MaxHits and MaxCombos (stage 1: 6 kills →
  200/330; stage 7: 25 kills, hits 7, combos 5 → 200/330). The score
  counter animates; a treasure still counting in at the first panel
  frame explains the few larger differences (e.g. +1600 at stage 17).
- Ambiguity recorded: the recording's two continues (score resets at
  stages 11 and 26) coincide with the bracket changes, so a rule based on
  continues or lives cannot be excluded; the stage-number bracket is the
  implemented default. Owner decision attached in ADR-0012.

Implemented: `EnemyArchetypes.Attributes.rewardCategory` (the §8.2
column, now verified as the table category); `ScoreRules` (GameCore data:
tiers by stage number, `rewardMultiplier`); `StageState.clearBonus` set
by the builder from the required content field `stageNumber` (validator
1…999; VS-01 states 1); the bonus is paid to every active player on the
deciding tick after `stageWon` with a `stageClearBonus(tally:reward:)`
event, checksummed and bounded, decoding as `.none` when absent; a lost
stage pays nothing. `KillTally` groups kills by category with row counts,
subtotals and the weighted total; `StageFlow` adds the `.reward` cue 18
ticks after the total line on a won stage with a bonus (hold stretched);
the controller withholds the tally bonus from the HUD score until the
total line and the reward until the reward line, so the shown score
counts in as the reference does while the world's score is final at the
decision; the panel shows the four category rows, "总计", "奖励 +N" and
the score. Not implemented (owner decisions in ADR-0012): MaxHits /
MaxCombos (semantics unknown), tank icons, a reward sound.

Icons (owner: "坦克图标"): `PixelTankIcons` composes one up-facing enemy
tank per category from the rig's tread, hull and turret sprites (the same
mapping the scene uses, now shared as `PixelTankNode.appearance`), cropped
to the rig body bounds (32×26 px) and drawn nearest-neighbour; the view
builds the eight icons once from the scene's art when the panel is about
to show and falls back to the category label if the art is unavailable.

Tests: `ResultsIconsTests` (every category renders an opaque 32×26 icon;
the mapping), `ScoreRulesTests` (tiers, categories, payment on the deciding tick,
no double payment, loss pays nothing, checksum/invariants, legacy decode),
`StageFlowTests` (reward cue timing and gating, category grouping),
`StageContentTests` (stage number required, tier selection),
`StageFlowIntegrationTests` (HUD payout pacing, five tally ticks, reset
with the world). Claude-only: PI was unavailable (usage limit).

## Designed outro and the centred results card (owner feedback 2026-09-10 late evening)

Owner, on the device with the first icon panel (verbatim): "结束了不管是全军覆没还是
胜利了或者输了，可以设计一个好一些的转场。转场完了播放类似这样的总结页面，但这个起码得居中，并确保
不同数字的时候也是能够对齐的". Applied:

- The outro is now a DESIGNED transition (the intro keeps the reference's
  measured timings): 0.8 s freeze while the decisive effect plays out; the
  outcome title stamps into the centre (scale 2.6 → 1 spring) with a
  screen flash (white on a win, red on a loss) and, on a loss, a decaying
  shake, over a one-line reason ("敌军全部歼灭" / "基地被摧毁" / "所有坦克损失");
  1.4 s hold; 0.7 s in which the title glides to the top at 60 % size
  while the scene drops black tiles over the arena from the edges to the
  centre (`StageFlow.coverStep`, a closing box iris — the reverse of the
  intro's growing cross); then the results card pops in centred (scale
  0.85 → 1 spring) and the tally runs as before. The HUD hides once the
  curtain is down; the card carries the score. `StageFlow.Durations`:
  outroDelay 48, outroText 24, outroHold 84, outroFade 42, panelIn 21.
- The card is centred (46 % of the width, at most 420 pt), and every
  number sits in a fixed right-aligned monospaced column with plain
  digits (no grouping separators): counts three digits, subtotals four,
  the total five — different values keep the columns aligned.
- Tests: `StageFlowTests` (outro length 329 ticks; the cover advances
  monotonically during the fade and stays closed), `OutcomeTitleTests`
  (subtitles). The sequence was captured frame by frame in the simulator
  on a loss; the owner accepted the transition and the card on the device
  ("我觉得挺好", 2026-09-10 late evening).

## M4 item 1 — campaign progression (2026-09-10 late evening; ADR-0013 proposed)

Owner: "把前 5 项给做完吧" and, for the maps, "按照原来地图，但是适配新的屏幕比例，允许你在
原版基础上按照你认为最合适的方式自由发挥". Landed:

- Content: `frontier_02_hidden_in_grass` (water channels, foliage cover,
  brick blocks, steel plates; 22 enemies: Normal A/C, Rapid A/B, Fire A)
  and `frontier_03_desert_stairs` (steel staircases on open sand; 24
  enemies incl. Explosion A, AP A/C), both read from the reference
  recording's play-start frames and re-drawn for 56×27 with the owner's
  latitude; `Content/campaigns/campaign_v1.json`; the registry's seeded
  placeholder ids replaced; the content validator checks campaigns
  against stages (existence, number = position).
- `SessionState` (carried lives/score/ammo/retained upgrades; armor
  resets), `CampaignRun` (stage index + checkpoint), builder/loader
  `session:` parameter with domain checks, replay format 4 with the
  campaign header and `ReplayPlayer.replayCampaign` (chain check,
  outcome required), controller campaign walk (automatic advance with
  the exit state, retry from the checkpoint, "战役完成 / 再来一局" after the
  last stage, completed recordings kept as the run's campaign replay).
- Tests (272 / 67): `SessionStateTests`, `CampaignRunTests`,
  `CampaignReplayTests` (three real stages chained; tampered header and
  undecided stage refused), the controller campaign test (advance, carry,
  retry from checkpoint, completion, restart), every shipped stage
  validated/built/numbered, replay format 4 boundary.

## M4 item 2 — screen flow (2026-09-10 late evening)

Plan §12.1 "Title → Campaign / Stage Select → Stage Intro → Gameplay →
Pause (overlay) → Stage Results → Next Stage / Retry / Exit", provisional
text treatment (no Phase 1 art):

- `AppRootView` renders `AppFlowModel` (pure state: title, campaign
  select, playing; stage unlock = first or predecessor completed;
  suggested stage = first not completed; completed stages recorded per
  app run until the checkpoint save lands). Title: 开始战役 / 训练场.
  Campaign select: one card per stage (number/subtitle from the id,
  已通关 / 可进入 / 未解锁, suggested card highlighted), 返回. The game screen
  gets an exit callback (返回标题 on the pause overlay, on a loss and after
  the campaign completes). Launch environment: `SPARKTREAD_AUTOSTART=1`
  skips the title into the campaign (the render smoke test uses it),
  `MOVEMENT_LAB=1` into the lab.
- Pause is an explicit controller state (ADR-0007): `pause()` stops the
  clock and closes the input gate, `resume()` restarts with a fresh
  clock; activations do not lift a pause. Losing the active state
  MID-PLAY becomes a player-visible pause (the overlay waits for 继续);
  during an intro, outro or results it just suspends and resumes as
  before. The pause/back action (§6.3) is keyboard Escape/P and the
  gamepad Menu button (provisional bindings) plus a HUD button; the
  press is an edge outside the activity gate (the same key resumes) and
  is polled by the view's flow timer, not the tick. Overlay: 继续 /
  重新开始本关 / 返回标题.
- Tests (279 / 70): `AppFlowModelTests`, `PauseBindingTests`,
  `PauseLifecycleTests` (clock stopped, input refused, activation keeps
  the pause, inactivity mid-play pauses, intro just suspends, restart
  clears the pause).
- Not in this item: settings, input-selection screen, accessibility
  options (M4 "settings, accessibility baseline, controller support" is
  the owner's item 6).

## M4 item 3 — checkpoint save and suspended session (2026-09-10 late evening; ADR-0014 proposed)

- Documents: `CampaignProgress` and `SuspendedSession` (versioned,
  self-validating), `SaveSchema` version gate (migration table empty at
  version 1), `CampaignPersistence` protocol, `InMemorySaveStore`,
  `FileSaveStore` (Application Support/SparkTread, atomic sorted JSON,
  version read first, errors not crashes).
- Controller: the snapshot is written on inactivity mid-play (before the
  clock stops), cleared on decision and abandonment; progress is
  checkpointed after each won stage (next run as checkpoint, best
  score); `init(resuming:)` continues the snapshot's recording, skips
  the intro and opens paused; failures land on `persistenceFailure`.
- Title: 继续上次战斗 (snapshot) / 继续战役 (checkpoint) / 新的战役 / 训练场,
  store notices; declining the snapshot discards it; stage cards start
  the checkpoint run when it is that stage.
- Tests (290 / 74): documents and version gate, snapshot → resume equals
  an uninterrupted run (session and controller), the resumed recording
  replays as one recording, write/clear/checkpoint timing, a failing
  store reported not fatal, file store round trip / foreign version /
  corrupt file.

## M4 item 4 — difficulty profiles and director phases (2026-09-10 late evening; ADR-0015 proposed)

- `EnemyBehaviorProfile` in `StageState` (decision interval, base-focus
  scale, wander, fire-window scale, mine roll, course commitment;
  checksummed, range-checked; `.standard` = the previous constants);
  the enemy brain reads it. `DirectorPhase` list + cursor in
  `StageState`; the director fires phases once in order (reinforcements
  jump the queue, cap change, base repair) with events, a HUD notice and
  cues. VS-03 authors the elite mine-layer wave after 16 spawns.
- `DifficultyDefinition` content (casual/standard/veteran; behaviour,
  telegraph percent with the 45-tick floor, composition variant,
  allied base damage Off/On/On, enemy ammo percent recorded only), the
  loader/validator, the tool requiring the three presets; the builder
  applies it; `CampaignRun.difficultyID`; replay format 5 with the
  difficulty in the header; the stage provider hands the session the
  difficulty's weapon rules; the stage-select difficulty picker.
- Tests (304 / 77): profile validation and effect (closed window never
  fires, wide fires more, interval paces decisions), phases (once, in
  order, cap, repair, paired carriers), presets load and differ as the
  plan intends, variants and the floor, builder application, run and
  header naming, notice raise/expiry, app-flow difficulty choice.

## M4 item 5 — deferred mechanics (2026-09-10 late evening; ADR-0016 proposed)

- Traversal profiles: `TraversalProfile` from equipment; water blocks all
  but AmphiTank through `TerrainKind/TerrainGrid.blocksTank(profile:)`,
  `Simulation.ObstacleField` (the mover's profile; a tank that loses
  AmphiTank over water may leave, never re-enter) and `Navigation`
  (profile beside `canDig`; the brain passes its own).
- Ice inertia: `MovementRuleset.iceSlideDistanceSubunits` 1536; centre
  cell on ice + no AntiSkid → release or direction change slides the
  distance along the last travel direction at normal speed; input turns
  the facing only, the slide direction cancels; blocks/leaving ice end
  it. Enemies too. The M1 movement golden was regenerated (note in the
  test: the script crosses the lab's ice patch and turns on it).
- Foliage: scene overlay at z 520 (tanks 500 < foliage < mines 600),
  47-joint textures with a slow frame cycle, 45 % fade over the player's
  footprint; presentation only (AI perception §24 Q8 open).
- Mine launch: `WeaponRuleset` launch distance/airborne/slow per level
  and the enable switch, `MovementRuleset.slowedSpeedPercent`;
  `TankState.landingSubunits` (checksummed, invariant-bound); the
  triggering survivor (Memory of Sea exempt) flies along its travel
  direction, suspended from movement, fire, targeting, blasts, flames,
  mines, pickups and blocking; lands by ring scan when the status
  expires; slowed after. Scene: a scale bump on launch, reset on landing.
- Replay format 6. Tests (319 / 81): `TraversalProfileTests`,
  `IceInertiaTests`, `MineLaunchTests`, the foliage presentation test.
- Not done (recorded in the ADR): the §15.3 per-archetype reachability
  waiver, foliage flammability and AI perception, wake/skid decals and
  a landing effect, a wake for amphibious tanks.

## Training Arena (owner direction 2026-09-10 late evening)

Owner (verbatim): "训练场应该有各种地形，所有类型的坦克，所有类型的砖墙，并且可以自由选择掉落不同的
装备，选择不同的子弹。所有类型的坦克也可以活动并且发出它们该有的导弹，只是我死亡之后可以无限复活，
以及自己的老家无法被摧毁。敌方坦克死亡会立即复活。另外，现在的武器和暂停按钮重叠在一起无法点击选择".

- `TrainingArenaFixture` (GameApplication): every terrain kind, all eight
  damaged-brick and four damaged-steel quadrant states, a water pool with
  a foliage shore, an ice rink, a foliage patch, a mixed fortress, the
  base with its brick U; all 24 enemy archetypes on a parade ground with
  the director's attributes and their family weapons; a stage (phase
  playing, empty queue) so the brain and the player lifecycle run; the
  base at 999/999 and the player at 999 lives.
- Arena rules (`MovementLabSession.trainingArena()`, lab only, outside
  the command stream — each intervention rebases the recording): a
  destroyed enemy respawns at once (same archetype, round-robin spawn
  cells, nearest free footprint), the base is repaired to full every
  tick, lives are topped up when low. `debugSpawnPickup` drops any of
  the 25 known pickups one cell ahead of the player.
- UI: the pause button moved to the top-LEFT; the top-right "训练面板"
  (collapsible, scrolling) has the weapon and power selectors, the
  pickup spawner grid and 重置训练场. The M1 movement fixture and its
  golden are untouched (the arena is a separate fixture).
- Tests: `TrainingArenaTests` (contents, enemies drive and fire several
  families, respawn/repair/lives, pickup spawner, the flag).
- Owner, on the device (verbatim): "一种类型的坦克一个就可以了；另外带红圈的坦克是什么，
  红圈位置也不对啊". Applied: the parade is one tank per weapon family (the
  A tiers; 6 tanks); the "red circle" is the §10.6 danger telegraph of
  the AP/Explosion/Fire/Mine families (a dashed ring with a warning
  triangle, tinted per family, bright when ready to fire) — it was
  drawn floating above the tank at 0.7 scale, which read as a misplaced
  circle; it now encircles the tank on its ground pivot at full scale.

## Owner rules of 2026-09-10 late evening (ADR-0017, accepted)

Verbatim: "训练场还是改成我点击一个按钮增加一个类型的坦克吧，不同类型的坦克按照抵抗力从低到高排序
让我选择"; "火焰弹打到草坪的时候，应该需要把相邻的草坪都点着"; "移除掉红圈这个设计，不需要警告".
Applied: the arena starts empty and the panel adds one archetype per
tap (24 buttons, resistance ascending, "清空敌人"); flames on foliage
spread to the neighbouring foliage after 20 ticks and burn it to ground
(ruleset data; ownerless spread patches; burned-grass decal; replay
format 7); the §10.6 danger telegraph is removed. Tests 331 / 82.

## Owner follow-ups (2026-09-10 late evening, second device look)

- "带月牙的坦克，月牙的位置错了": the vendor's four `px_equipment_moon_*`
  sprites all draw the crescent on the tank's RIGHT (the plow belongs at
  the front); `PixelTankNode.setEquipment` now uses the right-facing
  sprite rotated to the facing (`frontRotation`). Amphi/AntiSkid skirts
  and the Memory of Sea sensor keep their per-facing sprites (they were
  drawn correctly).
- "每种坦克一个按钮，点击这个按钮之后让我选择这个坦克的火力等级以及它可以搭配的装备": the
  training panel offers six family buttons; choosing one shows 火力 P0–P3
  and 装备 (无 / 两栖 / 防滑 / 月牙 / 海忆) and an 添加 button; the tank is the
  family's A archetype with those overrides, and respawns with them.
- "你是不是缺少能在冰面上走的装备": 防滑 (`anti_skid`) is that equipment — the
  traction profile never slides (ADR-0016); it is in the pickup spawner
  and the enemy equipment picker.

## Reference rules reverse-engineering (owner direction 2026-09-11, in progress)

The owner replaced rule-by-rule decisions with: derive the original's rules
from the reference video (all 31 stages) — shells, terrain, equipment,
brick × shell, tank × equipment × terrain, and their combination — into one
document, reach consensus with PI, have the owner review it, and only then
delegate implementation to Opus-class agents. State:

- `GAME_RULES.md` (v1.0) is now the single rules document: it merges the
  former `GAME_MECHANICS_SPEC.md`, `RESEARCH_SUMMARY.md` and the video
  work. Evidence tags 【V】video / B / C decompile / M modern (M-ADR vs
  M-临时) / ? owner; video measurements live in §3.4, §4.5, §5.4–§5.6,
  §6.3, §7.1–§7.2, §8.4, §10.4; the interaction matrices (shell × terrain,
  shell × tank, terrain × equipment, equipment × mine, combinations) in
  §17; the deviation list D-01…D-23 in §18; what the video cannot answer
  in §19. PI's
  round-32 frame check rejected the world half's high-impact claims
  (hits-to-kill anchors, Armor Up +1, kill-site drops, death resets,
  "steel U" base ring, Explosion-only steel damage): they are recorded as
  observations with unresolved attribution, and D-16…D-23 are framed as
  design choices for the owner (keep accepted policy unless the owner
  chooses otherwise), not as restoration fixes.
- Notable corrections to earlier assumptions (after PI's round-30
  cross-check): the reference base cell is 12 px in the 480×360 encode
  (tank = 2×2 cells), so Normal is 15.75 cells/s and the current code's
  11.25 cells/s (LV0–1) is 29 % slower than that unclassified-level
  sample; Fire is a visible delivery round that leaves persistent fire
  where it stops (rendered footprint 2×2 / 2×1 base cells, visible burn
  ≈5.5–5.8 s in the inspected samples, no attributable autonomous spread
  in the inspected non-foliage samples); AP/Explosion accelerate (caps
  unmeasured); the player's Rapid speed could not be attributed (the fast
  rounds at t=2465 belong to an enemy); mines were not identified in the
  recording. PI's round-31 wording review (video observations must not be
  promoted to immunity/absence/cap claims) is applied.
- PI's round-29 inventory (R29-01…25, verified with probes against
  `30af2b9`) is the "current code" column; R29-17 (Bomb damages airborne
  tanks) is a plain consistency defect to fix without a decision.
- Nothing in the code changed for this work; no implementation before the
  owner confirms §9.

## GAME_RULES R5 consolidation (2026-09-15; ADR-0018 accepted)

The owner asked for three steps: review the RC4 rules draft with the Astra
agent and settle disagreements, make the agreed document the single rules
authority, and move the code onto it.

Review. Claude and Astra (Codex, gpt-6-astra) exchanged three written
rounds plus two verification passes (`final agree`). The agreed changes are
listed in `GAME_RULES.md` appendix B (B.1 cross-review, B.2 final check):
AP against steel, the per-column damage strip, fire-landing geometry,
input buffering and the press-edge fallback, exact milli-subunit motion,
immediate explosions in the contact queue, blast occlusion along shared
edges, the water-exit rule, ice-slide details, source-keyed ground fire,
fort records, win priority, pickup placement, AI dig ability, results
categories, MaxHits/MaxCombos and the stall pause.

Documents. `sparktread-final-rules-review.md` became `GAME_RULES.md`; the
old research compendium and `PROJECT_MASTER_SUMMARY_ZH.md` were retired
(commit 4f2705e keeps them). The plan's gameplay sections 6–10 are an index
into the rules; ADR-0004/0010/0012/0015/0016/0017 are marked superseded in
part; asset lists drop mines and the two removed equipment items.

Code. GameCore now implements R5: layered terrain cells (surface under
walls and foliage), 4 915 200 mSU/s tanks starting at speed level 1,
integer shell integration with signed acceleration and per-weapon
lifetimes, the 10-tick normal-fire buffer and press-edge fallback, failed
shots without cooldown, the four-column strip with first-material columns,
immediate explosions with snapshot occlusion that ignore shells, symmetric
shell clashes without effects, the muzzle-in-wall launch contact, fire
shells landing clipped 2×2 footprints, source-keyed patches with a
per-victim 30-tick cadence and base edge contact, once-per-cell foliage
spread and burn-out, 2×2 pickups with a reachable placement queue and
critical pickups, Bomb clearing, Hold covering protected enemies, fort
templates with recorded originals and deferred per-quadrant restores, the
first-wave-then-30-tick spawn cadence with reserved spawn points and a
45-tick no-fire protection, loss priority with pending respawns, kill
attribution, MaxHits/MaxCombos, the water exit, and ice slides that keep
their speed and stop off the ice. Mines, mine launch, Shield of Moon and
Memory of Sea are gone from state, events, content, UI and audio. The
adapters fit the arena inside the safe area, space the fire buttons 96 pt
apart with weapon icons, show reserve/waiting/on-field counts and the
statistics, and pause on a frame gap above 250 ms. Replay format 8.

Golden regeneration. `M1MovementGolden` was regenerated because GAME_RULES
§4.1 raised the player base speed (2880 su/s → 4.8 cells/s) and R5 widened
the checksum surface; `MovementLabFixture` itself is unchanged.

Tests. Old combat, contract, mine-launch and foliage-fire suites that
encoded removed mechanics were deleted; `R5WeaponWallTests`,
`R5ExplosionFireTests` and `R5StageRulesTests` cover the §14.3 scenarios
that apply to the kernel; the remaining suites were updated to R5 values.

Not done in this pass: the twelve-stage content of §14.1 (three stages
exist, updated to R5 with fort templates), physical-device checks of §15,
and the §17 balance watch items, which wait for the owner's playtest.

## R5.1 speed tuning (2026-09-15; ADR-0019 accepted)

After the first device run the owner found movement and shells too fast and
asked for both to be lowered. Every tank and shell speed was scaled by 0.8:
player base 3 932 160 mSU/s, shell speeds and caps ×0.8, accelerations ×0.64,
lifetimes ×1.25, so ranges stay those of R5; normal and rapid in-flight caps
×1.25. Cooldowns and other timers are unchanged. `GAME_RULES.md` is now R5.1
(§4.1, §5.2, §5.3, §9.1, §17, appendix B.3).

Golden regeneration. `M1MovementGolden` was regenerated because GAME_RULES
§4.1 lowered the player base speed again (R5.1); the fixture is unchanged.
Recordings embed their rulesets, so the replay format stays 8.

## R5.2 speed tuning (2026-09-15; ADR-0019 amended)

After trying R5.1 the owner found the game still fast and asked for another
50 %. Tanks and shells now run at 40 % of R5 (player base 1 966 080 mSU/s,
shell speeds and caps ×0.4, accelerations ×0.16, lifetimes ×2.5); ranges
still match R5 within 0.15 cell. Normal and rapid in-flight caps grew with the
lifetimes (20/24/28/36, 60/70/80/90). `GAME_RULES.md` is R5.2.

Golden regeneration. `M1MovementGolden` was regenerated because GAME_RULES
§4.1 halved the player base speed again (R5.2); the fixture is unchanged.

Observation for the owner: at this tempo the Training Arena enemies took more
than 15 seconds to line up a first shot (the test window grew to 45 s), and
AP A/C crawl at 0.288 cells/s. Tests that depend on speed now read the
provisional rulesets, so further tuning needs no hand-edited expectations.

## R5.3 normal-fire spacing (2026-09-15; ADR-0019 amended)

On the R5.2 build the owner found the normal rounds too dense: shells ran at
40 % speed while the cooldown stayed, so consecutive rounds sat 1.5 cells
apart instead of R5's 3.7. The normal cooldown now follows the same time scale
(14/12/10/8 → 35/30/25/20 ticks) and its in-flight caps are R5's 8/9/11/14
again; players and enemies share the weapon. Rapid, AP, explosion and fire are
unchanged. No golden moved (the M1 drive fires nothing).

## R5.4 AP against red brick, white wall colours, safe area (2026-09-15; ADR-0020 accepted)

Owner direction after a device run: AP twice as effective against red brick,
white brick milky white, white steel whitish. The AP strip is now 2 cells deep
in columns whose first material is red brick (white brick and steel keep
1 cell); the depth is chosen per column. The white tiers had never shown on the
device: `colorBlendFactor` multiplies, so near-white tints left them red and
grey. They now use CPU-recoloured atlas textures mapped by luminance (bevels
and joints kept), checked in simulator screenshots of the Training Arena.

Correction to the R5 entry above: the safe-area fit did not work on the device
— the SwiftUI proxy that ignores the safe area reported zero insets and the
arena ran under the Dynamic Island. The scene now reads the insets from its
SKView; the simulator screenshot shows the arena clear of the island.

## Wall colours and pickup icon size (2026-09-15, owner follow-up)

On the device the first white-tier colours (ivory against near-white) looked
the same. White brick is now a warm ivory and white steel a cool silver-blue
about 30 luma darker with deeper joints (ADR-0020 updated; checked in a
simulator crop next to red brick and grey steel). Dropped pickups drew their
32-px icon at 1.2× the art scale, 2.4 cells across a 2×2 area; the owner found
them too big, so the icon is now 0.9× (1.8 cells). Presentation only; pickup
contact still uses the 2×2 area.

## R5.5 AP against white brick (2026-09-15; ADR-0020 amended)

The owner confirmed white brick doubles too: the AP strip is 2 cells deep in
columns whose first material is red or white brick, 1 cell in grey steel.
White brick still cracks first, so two AP rounds open two cells and it keeps
twice red brick's durability. The weapon field was renamed
`brickStripDepthQuadrants`, so the replay format moved to 9 (format-8
recordings and suspended sessions are refused). No golden moved.

## 1UP crash, rapid spacing, harder white tiers (2026-09-15, owner follow-up)

1UP crash: the Training Arena starts at 999 reserve tanks; a second 1UP made
1001, past `WorldInvariants.maxLives`, and the debug-build invariant assert in
`MovementLabSession.advance` killed the app. 1UP now stops at the domain
limit; `TrainingArenaOneUpTests` reproduces the report (it failed with the
same assertion before the fix).

Rapid fire was dense for the same reason as normal fire: its cooldown now
follows the time scale too (20/18/15/13 ticks, caps 24/28/32/36; R5.6).

White tiers: the owner found ivory and silver-blue soft and alike and asked for
harder-looking colours built on red brick and steel. White brick is a pale
stone brick with deepened joints, white steel a polished silver plate with
near-black joints; checked in simulator crops against red brick and grey
steel (ADR-0020 updated).

## Opening cue matches the stage end (2026-09-15, owner follow-up)

The owner found the opening and stage-end music mismatched. The stage end is
the 决战坦克 results excerpt, a sampled drum loop; the opening was a louder
NES-style square-wave jingle. `sfx_stage_card` is now an original drum-led
cue in the excerpt's idiom: its measured sixteenth grid (≈127 bpm), grouped
fills, kick/tom/snare/cymbal kit in a small room, 8363 Hz 8-bit sheen and
similar loudness, with its own pattern and a C-minor stab arpeggio (ADR-0011,
new section; measurements in `Tools/reference_measure/README.md`). No audio
or hit pattern of the excerpt is reused, and no Battle City material is
involved. The audio check and its selftest pass; the device audition is
the owner's.

## Stuck reinforcements and the phase notice (2026-09-15, owner follow-up)

The owner saw the stage-3 elite reinforcements stop at the top and never
move. Cause: a spawn process may start on a point a tank still stands on
(§9.3 lets it wait), and tank movement and AI steering treated that
reservation as solid even for the tank inside it. The tank could not
leave, the process could not finish, and the stage could never be won.
Slow elites (AP C at 0.288 cells/s) made the overlap common. Movement and
steering now ignore a reservation the tank already overlaps; entering one
is still blocked. Two tests cover it (`R5 spawning and statistics`), and
both fail on the old code. No replay golden moved.

The owner also asked to drop the "精英部队来袭" text. The director phase HUD
notice is gone; the phase's sounds stay (ADR-0015 updated).

## Shell strength and invincibility (2026-09-15, GAME_RULES R5.7, ADR-0021)

The owner rejected "opposing shells both vanish" and chose strength, with
fire bursting on any shell. Normal and rapid shells cancel each other and
vanish against AP or explosion shells, which fly on; heavy against heavy
ends both, the explosion shell blasting where they meet; a fire shell lands
its flame wherever it meets any opposing shell. Invincibility doubled to
1200 ticks. The clash rule and the spawn-reservation fix change the
simulation, so the replay format moved to 10 (format-9 recordings and
suspended sessions are refused). No replay golden moved; the old
cancel-without-effects test was replaced by per-kind clash tests.

## AP C speed doubled (2026-09-15, GAME_RULES R5.8, ADR-0019)

After the stuck-spawn fix the owner saw AP C move but crawl and asked for
more speed. AP C now spawns at speed level −2 (0.576 cells/s, was 0.288),
the same as explosion C; AP A, B and D are unchanged. The archetype table
is not part of a recorded ruleset, so the replay format moved to 11. The
fortress-versus-sprinter test now uses AP A, still at −4.

## Post-R5 review and performance pass (2026-09-16, Claude solo)

Astra was offline (`herdr agent list` had no astra pane), so this round ran
without cross-review; findings below should be re-checked in the next joint
round. Scope: GAME_RULES R5.8 vs the tree, a full hot-path code review, and
the owner-reported symptom "sustained fire stutters tank movement and heats
the phone".

Rules-vs-code audit: every authoritative constant in R5.8 §2–§13, §15.3
(~345 values — motion tables, cooldowns/caps, strip depths, blast radii,
the 20-archetype roster incl. the R5.8 AP-C change, AI windows and
difficulty tables, pickup/fort/lifecycle timers, scoring) matches
`Sources/GameCore` and `Content/difficulties`. My own reading of
Simulation/Combat/Fire/Navigation found no rule deviation: the R5.7 shell
clash matrix, the §7 flame footprint/beat/spread/burn-out chain and the §6.4
occlusion model implement the letter of the rulebook.

The three shipped stages did NOT meet the §14.1 budgets (content, not
engine): stage 1 lacked 普通B and the comparable red/white brick targets
(no `white_brick` in any shipped stage); stage 2 lacked 普通D and 火焰B and
shipped no guaranteed fire weapon; stage 3 shipped no guaranteed
AP/explosion weapon and authored `maxAliveEnemies` 5 (rule says 6; 6 only
after the `elite_siege` phase). **Owner approved all six fixes on
2026-09-16** ("这几项都按照你的建议来就好"), applied the same day:

- Stage 1: composition 14×normal_a + 4×normal_b + 2×rapid_a; the two inner
  mid-row wall chunks ([15,13,18,14] and [37,13,40,14]) became
  `white_brick`, so the mid row reads red-vs-white at equal width and
  thickness on both flanks.
- Stage 2: composition 6×normal_a + 6×normal_c + 1×normal_d + 4×rapid_a +
  2×rapid_b + 2×fire_a + 1×fire_b (still 22); queue index 5 — a fire_a
  under the round-robin interleave — carries a **critical `fire_weapon`**.
- Stage 3: `maxAliveEnemies` 6 from the start; queue index 5 (ap_a)
  carries a critical `ap_weapon`, index 11 (explosion_a) a critical
  `explosion_weapon` — each teaching weapon drops from its own family.

Content-validator and the full test suite pass on the new content. No
stage golden existed yet, so nothing was regenerated.

Performance (owner symptom):

- **Root cause: device playtests installed Debug builds.**
  `Scripts/deploy-device.sh` built without `-configuration` and installed
  from `Debug-iphoneos` — the unoptimized (-Onone) kernel plus active
  asserts/invariant walks is exactly "stutters under sustained fire and
  runs hot". The script now builds and installs Release. The next device
  run must confirm free-provisioning signing under Release.
- Scene mirrors now run once per WORLD TICK, not per rendered frame
  (`MovementLabScene.lastMirroredTick`); events, audio, haptics, curtain
  and effect aging stay per frame. Intros/outros/results no longer re-run
  full mirrors 60×/s over a frozen world.
- The foliage and liquid tilers re-derive a cell's texture only when its
  joint mask or animation frame changes (`foliageAppliedKey` /
  `liquidAppliedKey`) instead of a `String(format:)` + atlas lookup per
  cell per frame, and share static neighbour tables.
- The lab overlay computed a full-world checksum per frame; it now follows
  the session's 60-tick checksum cadence.
- `Stage.runDirector` took the §2.2 collision inset as a hardcoded ±64;
  it now reads `MovementRuleset.collisionInsetSubunits` (behaviour
  identical for every shipped ruleset; no golden moved).

White-tier wall art (2026-09-16, owner: "最好需要做…让 astra 来做"): Astra
delivered `PixelWallsWhite.atlas` — 256 `px_white_brick_joint_MM_QQ`, 256
`px_white_brick_cracked_joint_MM_QQ`, 256 `px_white_steel_joint_MM_QQ`
(16×16, same joint/quadrant contract as the brick/steel atlases) plus
manifest entries, its own QA (`Metadata/white_walls*_checks.json`, not
bundled) and a pipeline doc. Verified here: 768 spec-conformant manifest
entries, files present, sha256 samples match; visual check confirms the
R5.6 reading (pale stone brick with deepened joints, clearly darker
cracked state, polished near-white steel with near-black seams and a
per-quadrant indestructible glyph — the brightest wall, distinct in
grayscale too). `refreshWallTexture` now prefers these dedicated textures
and falls back to the CPU recolour when an id is missing, so a partial
atlas can never blank a wall.

Documentation staleness fixed in the same pass (details in the git diff):
plan §24 questions answered by R5 marked resolved, weapon/equipment/
archetype counts aligned (4 special / 2 equipment / 20 types), D-016
superseded note, fictional repo-tree entries corrected, ADR-0019 scope
widened to R5.6/R5.8 and its stale format-8 claim corrected, the 2026-09-09
handoff bannered as historical, asset docs stripped of mines/telegraph/
engine-tread/48×27 leftovers, and both asset docs note that the white wall
tiers currently reuse recoloured brick/steel atlases (dedicated art is an
open owner item).

No gameplay rule changed and no replay golden moved in this pass; the full
gate (`Scripts/ci.sh`) passed after the changes.

## Fullscreen arena, enemy stall fix (2026-09-16, owner round 2)

**Fullscreen (GAME_RULES R5.9, ADR-0022).** Owner: "画面还是全屏吧…把边缘
safe area 变成精钢". `ArenaLayout` lost its safe-inset input — the fit is
min(surfaceW/56, surfaceH/27) over the whole screen, centred — and the
scene tiles the gutter with `px_white_steel_joint_15_15` (the new
PixelWallsWhite bezel). On notched iPhones the bezel bands sit exactly
where the cutout is; controls and HUD keep their safe-area padding.
Presentation only.

**Enemy stall (owner screenshot, stage 2).** Two deterministic AI defects,
both reproduced by the new `EnemyStallSoakTests` (three stages, 9000 ticks,
stall = 15 s without moving or firing) before the fix — enemy 5 (normal_a)
froze at subunits (7628, 4160) from tick 2400 to the end of the soak:

1. `computeIntents.free()` credited the §4.2 alignment snap to PARALLEL
   candidates. Movement only snaps on perpendicular turns, so a tank pushed
   off-lane by another tank (swept moves stop at arbitrary subunits)
   believed "forward is free via a half-lane sidestep" forever and pushed
   into its blocker without ever rerouting. The snap is now restricted to
   perpendicular candidates — exactly the moves the movement rules will
   take.
2. The stand-and-dig test probed 1.5 cells ahead of centre while the
   break-terrain fire branch probed 2 cells ahead — adjacent to a thin
   diggable wall a tank would stand (dig test hits the wall) but never
   fire (fire probe lands past it). Both now share the shot's own
   `Combat.firstSolidQuadrant` sweep, so "worth facing" and "the shot
   connects" cannot disagree.

AI behaviour changed → replay format (simulation version) 11 → 12 per §9.2;
old recordings and suspended sessions are refused. No golden regenerated:
the M1 movement golden runs the stage-free lab fixture, whose checksums do
not involve `computeIntents`, and its expected values are unchanged (full
suite green). The soak stays in the tree as a regression test.

**Audio consistency pass (ADR-0011 amendment 2026-09-16).** Owner: keep
the reference originals, fix inconsistent cues (the stage-entry cue named),
remove unneeded ones. Two steps the same day: the stage card first became
a plain 3.6 s slice of the results excerpt; the owner then asked for a cue
that is NOT the same as the stage end — style-consistent and driving — so
the final card is an original two-bar pattern re-sequenced from the
excerpt's own drum strokes (grid-sliced at the measured ≈0.118 s
sixteenth, roles picked by deterministic band-energy analysis; 4.26 s,
≈45 % denser in actual strokes than the source, ending on the excerpt's
own wash). The eleven provisional cues that were plain 22050 Hz synthesis
moved into the generator's native 8363 Hz pipeline (recipes unchanged,
reference sample-sheen added); `sfx_mine_place` (dead since R5) is
deleted. All 8 excerpts byte-identical; `check-audio` and its selftest
pass. The card runs ≈1.1 s past the ≈3.15 s intro into play (the accepted
2026-09-15 composition ran ≈1.7 s past) — owner device listen pending.

**Art and audio review (2026-09-25).** Owner: "review all the art resources
and audios, if you think there are some issues, fix it directly. For the
audio part, try to align the opening style with the ending audio style."

*One rendering defect, found by capturing the real app.* The delivery
manifest and the atlases are internally clean (2385 sprites, every file
present, every sha256 matching, no unreferenced PNG, every sprite id the
Swift reaches — literal or composed — resolving), so the review moved to
simulator captures of the running app. Those show a vertical strip of
FOREIGN ground down the arena's right edge: flat green, pale blue and grey
blocks repeating every three cells against the frontier tan. Cause: the
ground is laid as 3×3-cell tiles and 56 is not a multiple of three, so the
last column group is clipped — and it was clipped with
`SKTexture(rect:in:)`, whose rect resolves against the PACKED ATLAS PAGE
rather than the sprite. `PixelGround` packs `frontier`, `floodplain`,
`frozen` and `citadel` on one page, so the clip sampled the other three
themes. 27 is a multiple of three, which is why only that one edge showed
it. The tests could not see it: they load the delivery's loose files, where
every texture is its own image and the sub-rect is correct; the smoke
render could not either, since its classifier only inspects the central
60 % × 50 % of the surface. The clip now crops the CGImage
(`MovementLabScene.clippedGroundTexture`, cached, falling back to the
unclipped tile) and `Scripts/check-architecture.sh` refuses
`SKTexture(rect:` anywhere under `Sources` so the class cannot return.
Re-captured: the edge is frontier ground to the boundary wall.

*The stage card, aligned to the stage end.* Measured against the excerpt it
is supposed to sound like, the 2026-09-16 card missed on three counts, all
now fixed in the generator's stage-card block:

| | stage end (excerpt) | card, 2026-09-16 | card now |
|---|---:|---:|---:|
| RMS | −20.8 dBFS | −23.5 | −21.2 |
| quietest 50 ms frame (p10) | −27.3 dBFS | **−120 (silence)** | −28.2 |
| 118 ms steps at digital silence | 0 of 35 | **10 of 36** | 0 of 28 |
| 250 ms envelope | flat, −19…−24 | −28 ramping to −18 | flat, −17…−24 |
| band split low/mid/high | −26.6/−28.9/−30.0 | −28.9/−31.1/−33.3 | −26.5/−28.6/−29.9 |
| strokes per second | 8.3 | 9.4 | 9.0 |
| last stroke | — | 4.07 s (≈0.9 s INTO play) | 3.13 s (as play opens) |

The gate was the real mismatch: a sampled room never falls silent, and the
card's rests were absolute zero. The pattern now plays over a room bed
built from the excerpt's own band above 2 kHz — grains half-overlapped
under a Bartlett window, read from positions advancing five eighths of a
step so none lands on the source's grid, every other one reversed, so
neither a transient nor a groove survives and what is left is the
recording's air. Level is no longer a constant but the excerpt's own
measured RMS (a re-extraction re-levels the card), capped at peak 0.9 so
the two cues can overlap at a stage change without reaching the mixer's
ceiling — that cap costs 0.4 dB of the parity. Bar one no longer plays at
0.85. The phrase is two bars of twelve sixteenths instead of sixteen, which
at the measured tempo lands the closing accent where the intro hands over
to play (card 2.3 s + reveal 0.45 s + title-out 0.4 s = 3.13 s) instead of
leaving a stroke ≈0.9 s inside gameplay; only the accent's wash rings past,
to 3.32 s. Still the same samples on the same grid, so timbre, tempo and
room are identical to the stage end by construction and the standing rule
holds: an original pattern, never the stage end's own passage, never
synthesized instruments, no Battle City material.

*Mix hierarchy.* Every cue's level was measured together for the first
time. The synthesized recipes were peak-normalised per voice and never
against each other, and three had ended up out-shouting the game: a shield
raise / base repair at −7.3 dBFS RMS was the LOUDEST sound in the product
(above the player's own death at −10.2 and a base breakthrough at −9.2),
the results tally tick at −8.6 stabbed 12 dB over the music it counts
against, and the wave-spawn warp at −10.2 was louder than every weapon
launch while firing on every wave and every director phase. Retuned by
their generator peaks only: `sfx_base_shield_on` −7.3 → −16.2,
`sfx_tally_tick` −8.6 → −18.1, `sfx_spawn_warp` −10.2 → −16.4. Nothing
else moved: the loud end is now base breakthrough, AP launch and the
player's death, then explosions and kills, then pickups and launches, then
impacts, then UI and music. `sfx_fire_ap` sits 6 dB over the other launches
(the owner asked for a missile that "sounds serious") — left alone, noted
for the device listen. Excerpts are untouched by construction; all 8 still
byte-identical, `check-audio` and its selftest pass.

*Checked and found clean.* Cue set and bundle agree exactly in both
directions (25 = 25, no cue in code without a file, no file without a cue);
ADR-0017 holds (the `px_status_danger` frames stay unused and the scene
says so); the white tiers draw the delivery's dedicated `PixelWallsWhite`
art, so the CPU luminance recolour is a fallback that no longer runs; no
`Current/`, `Tools/`, `Previews/` or QA JSON is bundled.

*Left for the owner, not changed here.* (a) Since the full-screen fit
(ADR-0022) the HUD pill and the pause button sit over live arena cells —
captures show enemy tanks behind both — which §15.1's "不透明 HUD 不覆盖关键
对象" speaks against; the fix is a layout decision, not a defect to patch.
(b) The gutter bezel is 精钢 as §15.1 requires, and §3.1 makes 精钢 the
brightest wall in the game, so the frame is now the brightest thing on
screen and pulls the eye off the field; dimming it would work against the
same rule's "不留黑边", so it needs the owner's call. (c) The delivery ships
a complete unused UI set (`PixelUI`, 46 sprites: joystick, control knob,
normal/special buttons, pause, panels, cards) while the touch controls and
pause are drawn as plain SwiftUI shapes — wiring it up is a visible look
change. (d) Art for mechanics R5 removed is still in the delivery and in
the adapter: `PixelMines` (8 sprites) with `PixelMineNode` and three mine
event recipes, the `mine_*` turrets, pickups 7/8/24, and the moon/memory
equipment with its rotation special case in `PixelTankNode`. Dead, not
wrong, and the submodule is a separate repository.

**Three cues reworked on the owner's listen (2026-10-01).** The owner
auditioned all 25 bundled cues and named three: `sfx_fire_explosion`
"有点闷，和别的音效感觉不太符合", `sfx_explosion_blast` "也有点闷",
`sfx_base_shield_on` "觉得很滑稽，有点奇怪". Each had a measurable cause —
the demolition launch was led by a 160→65 Hz square glide and sat 9 dB
heavier in the bass than the reference shot excerpt beside it; the blast
was 3.4 dB thin through 400 Hz–1 kHz (the band the reference's own
explosions put their body in) with 6 dB more mud under 150 Hz; the shield
cue was a rising square GLIDE, which is what read as cartoonish. All three
are rebuilt crack-led with the bodies they were missing, and the shield cue
is now two struck metal plates rather than a glide. Details and the band
profiles are in ADR-0011's 2026-10-01 amendment.

The rework also exposed two gaps in the generator, both now closed:
`write_native`'s `peak` says nothing about how loud a cue lands, so
rebuilding a recipe silently re-levelled it (these three came out 5, 5 and
13 dB under what the 2026-09-25 mix pass had set) — a reworked cue now
declares its target RMS through `write_native_rms` and a capped peak is
printed; and a crack-led recipe cannot reach its loudness inside the
headroom ceiling while one transient sits 16 dB above the body, so
`saturate` rounds that transient instead of trading bite for level. All
three land within 0.1 dB of their 2026-09-25 loudness, so the owner's A/B
is timbre only. The other 14 synthesized cues and all 8 excerpts are
byte-identical; the full gate passes. Owner listen pending on these three.

**Whole-cue-set review, and the card rebuilt as a gesture (2026-10-01,
later).** The owner asked for the standard applied to the three named cues
to be applied to every cue, and settled the two stage cues: `sfx_stage_win`
is finished and must not be touched again, while the card "作为开场音乐非常
不合适，必须更改出一个配套的".

The card's diagnosis is worth recording because three attempts had missed
it. All three were grooves, and the 2026-09-25 pass had made the last one
match the stage end on every axis that can be measured — RMS, noise floor,
band tilt, stroke density, stroke placement on the source's own grid — and
the owner still rejected it. That locates the fault where the measurements
were not looking: form, not texture. A results screen keeps rolling, so the
stage end is a groove; a stage card has to announce and hand over. A loop
built from the groove's own samples is the same music arriving in the wrong
place. The card now keeps every matching property (same kit, room bed,
≈127 bpm grid, the excerpt's own RMS, still only the excerpt's strokes) and
changes only its shape: a run-up tightening BELOW the grid, a struck
statement, a short drive split by a second accent, a tom fill, and a crash
at 3.12 s where the intro hands over, ringing 0.47 s into play. Two further
shapes (`three_strikes`, `crescendo`) were built from the same strokes and
sent for audition; `SHAPE` in the generator selects the one that ships.

The rest of the set was measured for duration against its event's cadence,
level against its importance, and band tilt against the reference
excerpts. Seven cues changed and one was deleted — `sfx_fire_ap` was the
second-loudest cue in the product (−10.1 dBFS RMS, over a tank exploding at
−12.4); `sfx_base_own_hit` sat under every impact cue at −20.0;
`sfx_pickup_spawn` was 3 dB louder than collecting; `sfx_base_hit`, the
loudest cue in the game, had no body under 150 Hz; `sfx_spawn_warp` had a
crest factor of 1.0 dB, the constant-amplitude bare-square signature of the
shield whoop the owner had already rejected, and was the last one in the
set; `sfx_hit_brick`, the most frequent impact, piled its energy below the
crack; and `sfx_base_destroyed` was almost all hiss. `sfx_fire_special` is
removed outright: a third byte-identical copy of the shot excerpt kept for
a weapon id R5 cannot produce, so it could never play. Figures and the
reasoning are in ADR-0011's second 2026-10-01 amendment. `GameAudio`'s
rapid-fire voice pool was also found to document a cadence R5.6 replaced
(83 ms and five overlapping clips, now 217 ms and two); the six voices stay
as headroom per R18-01 and only the stale comments were corrected — shrinking
the pool would have traded a real safety margin for two preloaded voices.

Owner listen pending on all of it. The bundled set is 24 cues, 7 excerpts,
all byte-identical; the full gate passes.

**The stage card carries a tune (2026-10-01, third pass).** Having heard the
three drum-only shapes, the owner asked for a melodic opening and linked the
Battle City NES start theme as the model. Its melody is not copied or
paraphrased — the owner settled that on 2026-09-10 and the standing rule
came out of it — so what is taken is the function (short, rising,
announcing, resolving into play) and the notes are an original figure. The
instrument is the interesting part: a tune needs a pitched voice while
composing the card from synthesized instruments is separately forbidden, and
both rules hold at once by playing the melody on the excerpt's OWN pitched
drum, autocorrelated out of the passage (110.8 Hz) and resampled per note.
C minor pentatonic, from this excerpt's own measured harmonic stabs. It
lands at −20.8 dBFS RMS, identical to the stage end. The three drum shapes
are byte-identical after the change, so the earlier audition stands, and
`SHAPE` in the generator selects which of the four ships. Details in
ADR-0011's third 2026-10-01 amendment; owner listen pending.

**The owner supplies the stage card (2026-10-01, fourth pass).** After four
generated candidates, the owner committed their own stage-start audio
(3c0bc96) and directed that it be the cue. It is `sfx_stage_card.wav` now —
renamed to the name the code already uses — and bundled as given: measured
3.23 s, mono 22050 Hz, −20.8 dBFS RMS (the stage end's level exactly), band
tilt within ~1 dB of it, and 0.1 s longer than the intro, so it needed no
processing and is a closer match to `sfx_stage_win` than anything generated
here. That ends the search recorded in the three amendments above.

It did need a change to the pipeline. Every bundled file was either
generated and byte-compared or extracted and hash-compared, and a file the
owner hands over is neither, so the check rejected it. Attribution `owner`
now means verified by hash, never regenerated, and protected in the
generator against being overwritten; `check-audio.sh` splits by provenance
instead of by "is it an excerpt", with two new selftest cases for the class.
The stage-card generation block and the machinery that served only it were
removed — all four candidates are in git history at 1363851 — and the 16
remaining synthesized cues are byte-identical across the removal. Details
in ADR-0011's fourth 2026-10-01 amendment. What the manifest cannot state
is where the owner's audio came from; that line is theirs to give.

**The four open review items, done (2026-10-01, fifth pass).** The owner
took the recommendations from the art and audio review and closed the list.

*The controls became glass, by way of the delivery's art.* `PixelUI`
shipped 46 sprites and not one was referenced, so the first pass wired its
stick, thumb and fire-button discs into `TouchControlsView`. Seeing them on
the device the owner asked for the opposite — "操控面板还是用透明的有玻璃效果
的背景" — and they were right about the cost: the delivered discs are opaque,
so the pad hid whatever it sat on, and the pad sits over the playfield.

Glass by real blur does not work here. `UIVisualEffectView` cannot sample
SpriteKit's Metal output, so the material came out a flat opaque grey that
hid the bricks under it completely — worse than the art it replaced. It is
painted instead: a low-alpha channel tint the arena reads straight through
(cyan for the normal gun, orange for the special, matching the HUD's own
colour coding), a top-lit sheen that is gone by the middle so the lower half
stays clear, a 1.5 pt bright rim and one specular highlight. A press raises
the tint and the rim rather than moving anything. Deterministic, and it
looks the same over any content. `GlassDisc` in that file owns it.

§15.2's geometry is untouched throughout — 66 pt visible buttons, 45 pt hit
radius 96 pt apart, 12 pt dead zone, 36 pt leash, and the stick's 96 pt base
with its 44 pt thumb on the same ±34 pt clamp. `PixelUI` is unused again;
the owner has now seen both and chosen, which is worth recording so the
unused-art finding is not re-raised as a defect.

*The HUD gets out of the way.* Since the full-screen fit (ADR-0022) the HUD
has nowhere off the playfield to sit, and it sits on the top edge — which §9
makes the spawn lane, so an arriving enemy is exactly under it, which §15.1
speaks against. The owner chose the overlay fix over giving a row back to a
HUD strip, so the pill now reads its own frame, asks the scene whether a
live tank or shell is drawn under it (`drawsLiveObject(under:)`, node frames
only, nothing the simulation depends on) and thins to 0.4 while there is,
easing back over 0.18 s. 0.4 rather than lower because the top edge means it
will thin out often and must stay readable while it does.

*The gutter band recedes.* §15.1 dresses the leftover gutter in 精钢 and
§3.1 makes 精钢 the brightest wall in the game, so the frame was the
brightest thing on screen and pulled the eye off the field. The material
and the fill are unchanged — "不留黑边" holds — and the band is multiplied
34 % toward black so it sits behind the playfield. One constant
(`bezelDimming`) to revert.

*Rapid fire is audibly its own weapon.* `sfx_fire_rapid` was a third
byte-identical copy of the shot excerpt, so the special channel sounded
exactly like the normal one even though rapid is the weapon a new campaign
starts with and the one whose ammo you spend. It is now derived from that
same excerpt — replayed 12 % faster, which is also 12 % shorter, cut to
200 ms, levelled to the normal launch's own −16.3 dBFS RMS. 200 ms clears
the fastest cadence R5.6 allows (13 ticks, 217 ms), so a burst reads as
separate shots instead of one smear. The excerpt itself is untouched and
still serves the normal launch; it is no longer extracted three times, so
the set is 17 synthesized, 6 excerpts and the owner's stage card.

Three items were closed WITHOUT changes, deliberately: a separate cue for
base repair versus flag guard (both mean "your base just got better", and
the visuals already differ); a loss stinger for running out of lives (the
player's own tank explosion already plays, which is why the base needs its
own cue and this does not); and a cue for the results reward line (the
reference has no isolated instance to take, and synthesising one would add
a placeholder voice to a set that just lost two).

**The twelve-stage campaign, and the loose ends (2026-10-03).** The owner
played the three stages through ("体验还行") and asked for the rest of the
content plus the small cleanups that had been accumulating.

*Stages 4–12.* §14.1 already fixed every stage's teaching goal, enemy
budget, alive cap and required elements, so this was execution against a
written spec rather than design. Each map is laid out to teach its own
line: the river and its three bridges with flank channels only an
amphibious hull can use (4); a long straight ice lane kerbed in brick with
a dry detour beside it (5); red and white blocks of identical shape in
matched pairs, a four-deep white band, and steel pillars that shadow a
blast (6); three long lanes with the supply crates out on the flanks (7);
two unbreakable fine-steel spines whose gates are offset so the west and
east routes differ (8); grass fields broken by water, ice and a fine-steel
spine (9); an ice shortcut walled in steel against a slower brick detour
(10); a deeper fort with a top gate for the flag rotation to restore, and a
phase that repairs the base (11); and all eight terrain kinds with every
weapon family on the board (12). All twelve validate, build deterministically
and keep the base reachable on the undamaged map.

Enemy coverage was tracked rather than assumed: stages 1–3 introduce 14 of
the 20 types, and §14.1's required appearances bring in the other six —
`explosion_b` and `ap_d` at stage 4, `explosion_d` at 5, `rapid_d` at 7,
`fire_c`/`fire_d` at 9 and `ap_b` at 10 — so §16's "20 型全部在正式内容中
出现" is satisfied by stage 10, before the summary stage needs them.

The maps were authored as ASCII and converted to the schema's rects, which
is why the committed JSON still reads as rectangle lists: a 56×27 layout is
designed by looking at it, and the rect form is what stays diffable.

*The theme finally reaches the scene.* `themeID` has been in the stage
schema from the start and the delivery ships four ground families, but the
scene tiled `px_ground_frontier_*` unconditionally — correct while every
stage was frontier, wrong the moment stage 4 existed. `StageLoader.loadStage`
now returns the definition alongside the world (one decode, one validation),
`StageBuild` carries the theme, and the scene maps it to the family. A test
asserts every theme the registry allows resolves to nine tiles that exist,
so a theme added without art fails rather than rendering as sand.

*Two tests had to change, and one of them was over-specified.*
`everyShippedStageValidatesBuildsAndNumbersContiguously` compared stage
numbers in FILE-NAME order against 1…N. Stage files are named theme-first
and the file name has to stay the stage id, so the directory stopped
sorting by campaign position as soon as a second theme existed; the
invariant that matters — every number once — is now asserted on the sorted
list. The chained campaign replay was named and written for three stages;
it now plays the whole campaign and derives the expected score from
`ScoreRules.reference` per position instead of three pasted numbers, which
makes it §16's completion criterion ("12 关能从新战役打到结局") in scripted
form. It is still scripted instant wins, so it does not discharge the
played golden.

*The loose ends.* `MovementLabView` gained the `import Combine` its
`Timer.publish` needed (a standing build warning). The mine presentation —
`PixelMineNode`, its phase and surface enums and the three mine effect
kinds — left with the mechanic R5 removed, as did the Shield of Moon's
rotation special case and its test, since §8 keeps two equipment items and
neither is the moon; the art stays in the delivery, which is an archive,
but `PixelMines.atlas` is no longer bundled into the app. In the submodule,
`delivery_summary.json` still described the set before the white-wall
increment — 1617 textures across 17 atlases, with the delivery's largest
atlas missing from the counts and a stale manifest hash; the derivable
fields are recomputed and a `recountedFor` note says which figures are
still the earlier run's and where that increment's own verification lives.

**The select screen: a scroll bug, and art for twelve stages (2026-10-03,
later).** The owner found the select page unscrollable and asked for a
background behind every stage on it, then for the title and select screens
themselves, which were bare text on black.

*The bug.* The stage cards sat in a plain `HStack`. Twelve cards at 150 pt
plus spacing is about 2000 pt of row against a 956 pt screen, so everything
past the fifth stage was off-screen with no way to reach it — it fit while
three stages existed and broke silently when nine more arrived. The row is a
horizontal `ScrollView` now, and a `ScrollViewReader` opens it centred on the
stage you would play next rather than at stage 1.

*The card art is each stage's own map.* Rather than twelve drawings, a card
shows the place it loads: `StagePreview` (content layer, pure) replays the
terrain layers exactly as the builder stacks them and returns one value per
cell, plus markers for the base and the two kinds of spawn — the three
things that tell two maps apart at a glance. `StageCardArt` paints that at
one pixel per cell in a palette sampled from the delivery's own art (the
mean colour of each atlas face, measured the same day), so a card reads as
the world its stage renders in. Nothing new is bundled, the art cannot drift
from the content, and a thirteenth stage brings its own background.

Verifying it caught a real defect: a bitmap context's MEMORY is top-down
even though its drawing space is y-up, and flipping the rows on the way in
put every base at the top of its card and every enemy spawn at the bottom.
`StageCardArtTests` now asserts the base marker lands on the stage's own
`baseSpawn`, that all three markers exist, that no two stages render the
same card, and that the four themes reach four distinct ground colours.

*The menus.* `MenuBackdrop` builds the title and select screens out of the
game's own material: the steel plate the arena walls are made of, tiled at
whole-pixel scale, taken right down, under the same top light and vignette
the playfield reads with — so the menus sit inside the fortress the battles
happen in and the look cannot drift from the game's. A tank watermark was
tried twice and dropped: dimmed, a top-down tank is a smudge, and
stencilled from its alpha it is a rectangle, because that is the shape a
tank seen from above actually is. The plate carries the screens on its own.

**Select screen, second pass (2026-10-03, later still).** The owner sent a
screenshot: every card's title was clipped, the back button was too plain
and sat too low, and the app wanted a launch sequence.

*Two real defects behind the clipped text.* The card's map was a ZStack
sibling with `scaledToFill`, so the image drove the card's layout instead of
sitting behind it; the fixed frame then centred content wider than itself
and cut the title at both ends. The map moved into `.background`, which is
laid out to the view's bounds and cannot size it. And `HUDLabels.stageCard`
read the stage number out of id position 1 — fine for `frontier_01_…`, wrong
for `iron_citadel_08_…`, because the new theme ids are two words. Stages 6,
8, 11 and 12 showed "STAGE" with their number stranded in the subtitle. It
finds the number now, and the name is whatever follows it. Both are pinned
by tests, the second by asserting every campaign stage resolves to its
position and to a subtitle that is not ASCII — a Latin subtitle is the
fallback spelling of the id, so that check catches a stage that lost its
name as well as one that never had one. Stages 4–12 gained Chinese names,
each the line its map teaches.

*The back button* moved off the title's line; its styling was revised again
the same day (below).

*The launch sequence, and a wordmark (third and fourth passes).* The
owner's note on the fire-and-stamp version: the tank should drive past and
LEAVE the title behind it, and the title should be designed rather than set
in a plain face. Then, on the first cut of that: too fast, and drop 坦克大战.

The intro now: the player's own tank — the right-facing player rig,
composed from the same sprites the scene uses — drives across the title
band from off the left at one constant speed (170 pt/s); the wordmark is
masked by a rectangle whose trailing edge is the tank's rear, so what shows
is exactly what the tank has passed over, laid down over two dashed tracks
the width of the word; the buttons rise the moment the rear clears the
trailing edge, and the tank keeps rolling until it is off the screen. Once
per app start. The subtitle is gone, the wordmark went up a size to carry
the top of the screen alone, and the tracks got a little heavier since
they now say "a tank was here" by themselves.

Two faults were found and fixed by measuring, not by looking. First, the
tracks were a GeometryReader and took the whole screen's width — and the
title screen measures the wordmark to drive the tank, so the tank was being
run across the screen instead of across the word; the tracks hang off the
word as an overlay now. Second, and the real one: the tank's position and
the reveal's edge were both derived from one animated `@State`, which
LOOKS like they must agree, and they did not. SwiftUI does not re-run such
closures per frame; it interpolates each modifier between its start and end
values over the whole duration, and because the reveal is clamped to the
word, its edge crawled across the word for the entire run while the
unclamped tank moved at the declared speed. Timestamped screenshots put the
edge at ≈112 pt/s against a declared 270, with the buttons — timed by a
sleep that trusted the declaration — arriving at 80 % revealed. `TankReveal`
is now an `Animatable` modifier whose `animatableData` is the progress, so
SwiftUI interpolates the progress itself and re-evaluates mask and tank
together every frame; the buttons are a completion of the first leg rather
than a sleep. Re-measured: edge ≈180 pt/s, title complete before the
buttons appear. (Screen recordings were tried first and rejected as a
timing source: `simctl recordVideo` reported 4.8 s for 8 s of wall time.)

The wordmark is two of the materials the game is made of: "Spark" in the
fire yellow the menus accent with, graded down into orange, and "Tread" in
the delivery's own polished fine steel graded down into its plate (sampled
colours), on a hard extruded block — stepped copies, no blur, so it keeps
the edges pixel art has — with a dark rim, and the tank's tracks under the
baseline. `TitleWordmark` and `TankReveal` in `AppRootView.swift`.

*The back button, again.* Owner on the capsule: no border, too high, and
not good looking. So no frame at all — a yellow chevron and the word,
carried over the plate by a shadow rather than by a box, with the 44 pt
target kept by padding rather than by anything drawn — and moved down off
the screen's very edge.

Verified by rendering the views themselves (`ImageRenderer`) rather than by
driving the simulator, which needs an accessibility grant: the card layout,
the titles and the back button were checked that way, and the twelve card
images against the stage data. The scrolling itself is structural only —
`ScrollView` plus a `ScrollViewReader` that opens on the suggested stage —
and is for the device pass to confirm.

*The launch sequence has a sound (2026-10-03, owner follow-up).* The
owner asked for music under the drive — from the tank appearing to the
title coming out from under it — and said the music could be the sound of
its treads. `sfx_title_tread` is that, and nothing else: 5.3 s synthesized
in the native 8363 Hz pipeline like every generated cue, attribution
`invented` (决战坦克 has no tread sound; nothing in it is measured from the
recording). Two tracks of link slaps at 9.5 per second each, offset by 0.42
of a period and ±6 % jittered so the composite limps rather than ticks;
each slap a bandpassed clack (1.6 kHz), a brighter ping (2.5 kHz) and a
short ground thud (160→90 Hz); under them a rolling noise bed high-passed at
140 Hz so its weight sits where a phone speaker carries it — the first
drafts put 39 % of their energy under 150 Hz, which is the "闷" the owner
has rejected before — a metal-on-metal hiss that follows the slaps, and a
pitch factor that turns over as the tank passes mid-word. It is CUT TO THE
DRIVE: the tank's rear clears the 370 pt wordmark plus its own 66 pt at
170 pt/s, 2.565 s in, and from there the cue recedes −34 dB with its top
closing from open to 500 Hz, silent at 5.3 s when the exit run ends. The
envelope stops the sound, so nothing in the app has to, and
`TitleIntroAudioTests` holds the cue's length to `TitleScreen.introTimeline`
so the drive's constants cannot move without the audio moving with them.
Measured on the bundled file: steady part −20.8 dBFS RMS (the two music
cues' own level — it stands in for music), whole file −23.5; band shares
150–400 Hz −4.9 dB, 400 Hz–1 kHz −6.0, 1–3 kHz −6.2, under 150 Hz −9.2;
envelope autocorrelation peaks at 106 ms, the per-track slap period.

This narrows the 2026-09-10 no-engine-sound decision rather than reversing
it: the game still has no engine or tread voice, and the launch — outside
any game — is the one place a tank is heard moving. ADR-0011 sixth
amendment; the standing rule in CLAUDE.md now says so. Playback: the app
builds ONE `GameAudio` at the root, under the launch screen, so the voice
pools warm once instead of at the first game start; the title plays the
cue through it and every controller is handed the same instance (the
`audio:` parameter the controllers already took). The tread's pool is one
voice.

Two options were put to the owner, who answered 可以听你的意见. Taken: the
sound now MOVES with the tank — the only stereo cue in the set, panned in
the file by the tank's place on the screen (from 218 pt left of centre,
through the middle at 1.28 s, full right as it leaves; constant-power law
referenced so the centre equals a mono cue on both speakers, so it is no
louder in the middle and no quieter at the sides), which costs the mixer
nothing: iOS routes the built-in speakers by orientation. Measured on the
bundled file: left 5.3 dB over right in the first 0.6 s, equal through the
crossing of centre (0.9–1.6 s), right 13.5 dB over left at 3–3.6 s and
alone from 4 s, when the tank is off the edge; the two channels' power mean
over the plateau is −20.8 dBFS, the mono target. Declined: an accent when the
title is complete. The reveal already closes visually — the buttons rise at
that instant — and a stinger there would compete with the treads receding
and risk the 滑稽 the owner has rejected in a cue before; the soundscape is
one thing, a tank driving past, and stays that.

*Two shots on the way through (2026-10-04, owner follow-up).* The owner:
让坦克开过去的时候再放两枪，并加上两声子弹音. The tank now fires twice as
it comes in, and everything about the shots is the game's own rather than
invented for the title: the first at 0.4 s, the second at the normal gun's
LV1 cooldown after it (GAME_RULES §5.3, 35 ticks = 0.583 s, read from
`WeaponRuleset.provisional`); the shells outrun the tank by the game's
shell-to-tank speed ratio (6.4 cells/s over 1.92 — ×3.33, so 567 pt/s at
the intro's 170 pt/s, read from the same rulesets); the shell is
`px_projectile_normal` and the flash `px_fx_muzzle_0` at the scene's own
proportions to the tank (0.8 and 0.48 of the art scale), turned a quarter
to face the drive, the flash placed by the manifest's anchor on the
manifest's muzzle point for the right-facing player rig (not a number read
off a screenshot); and the voice is `sfx_fire_normal`, the reference's own
shot, twice, over the treads. Both shots fall while the tank is over the
word (0.4 s and 0.98 s against a 2.57 s crossing), so the shells streak
across the still-unrevealed band ahead of it and leave the screen on their
own. The drive is now four linear legs instead of two — a leg ends at each
shot and at the crossing, every boundary a completion — so the voice fires
at the frame the shell appears, and the shells themselves are drawn from
the same interpolated progress the tank moves on. `TitleIntroAudioTests`
holds the shots inside the crossing at the gun's cadence. Verified on the
simulator with timestamped screenshots: the first shell ahead of the tank
as "S" comes out, the flash on the barrel tip pointing right as the second
fires, both shells in flight over the unrevealed band.

*Sparks off the tracks (2026-10-06, owner follow-up).* The owner, happy
with the sequence, pointed at the app icon: its tank kicks up flecks behind
its treads, and the intro's should too. The trail is a pure function of the
same interpolated progress everything else moves on — one fleck per 3 pt of
travel, each thrown back and up from where the rear of the tracks met the
ground at that moment and dropping under a small gravity, living 54 pt of
travel, so about eighteen are in the air at once; sizes 1, 2 or 3 of the
tank's own pixels (the 3s are soft puffs at 55 %), colours the icon's cream
and orange, every fleck's variation from an integer hash of its index so
no RNG runs in a view body and a frame that shows the same moment shows
the same cloud. The first cut trailed too far back and too thin (a line of
dust specks); the second gathers the cloud right behind the rear wheel as
the icon does. Verified on the simulator: the cloud behind the wheel over
the tracks as "Spar" comes out. Knobs, should the owner want it denser or
longer: `sparkSpacing` and `sparkLife` in `TankReveal`.

*The launch page (2026-10-06, owner follow-up).* Between tapping the icon
and the title there was a black card; the owner asked for a page that
flows into the intro. A launch screen runs no code and (via Info.plist
`UILaunchScreen`) shows one image centred at its intrinsic size over a
colour, so the only way it and the live title can agree to the pixel is
for both to be the same picture anchored at the same point: `MenuBackdrop`
is now composed on a FIXED 1024×512 pt field centred on the screen (plate
grid, top light, vignette all inside it; the base colour fills the rest),
and the launch image is a render of that field — `MenuBackdrop.Field`
through `LaunchImage.render`, written at 2× and 3× by the new
`launch-screen-renderer` executable into the app's asset catalog, with
`LaunchBase` as the colour. `LaunchScreenTests` re-renders the field and
compares it with the committed PNG (≤ 3 levels per channel), so the
backdrop cannot change without the launch image being re-baked. On the
title the tank now fades in over its first 40 pt of travel
(`arrivalTravel`) rather than popping onto the hand-off frame. A launch
storyboard was tried first and dropped: the iOS 26 simulator never showed
it, nor — it turned out — any launch screen at all: with the plist form it
shows the system background (black in dark appearance, white in light),
though `Assets.car` carries both `LaunchBackdrop` and `LaunchBase` and the
plist carries the dictionary. The device is the judge; owner to confirm
the hand-off on the phone. The field covers every iPhone (956×440 pt at
most); iPad would need a larger one. Confirmed by the owner on the phone:
出现钢板背景.

*One button language (2026-10-06, owner follow-up).* The owner: the
buttons looked like stock controls, and "风格" meant arrangement as much as
looks. `PlateButton.swift` now holds the language for every screen, taken
from the wordmark: the two materials the game is made of — the fire yellow
for THE action on a screen, the arena's steel for everything else — on a
hard extruded base with a dark rim and a top sheen, squared corners rather
than capsules (they are plates, like the walls), and a press that sinks the
face onto its base. Three sizes (large / regular / small), a `selected`
state that turns a steel toggle to fire, a `PlateSegments` row for the
difficulty, and a `platePanel` for the overlays — dark steel with a rim
and its own base — replacing the yellow-framed boxes with white pills.
Arrangement rule, applied everywhere: one primary plate, large, alone on
its row; the secondaries in one row under it. So the title shows the one
thing to do by the player's state — 继续上次战斗 / 继续战役 / 开始战役 — and
新的战役 and 训练场 under it; the pause overlay 继续 over 重新开始本关 and
返回标题; the results footer 重新开始 (or 再来一局) in fire and 返回标题 in
steel; the HUD pause button a small steel plate with the atlas's pixel
pause glyph; the training panel's toggles small plates, the chosen one in
fire. Labels stay native text with a symbol in front. Verified by an
offscreen gallery render of every variant (including disabled) and
simulator shots of the settled title and the arena HUD.

*The results page waits for the player (2026-10-07, owner follow-up).*
Owner: longer transitions between stages, and the results page should
wait for a tap before the next stage. A won campaign stage no longer rolls
into the next one by itself: the flow's `wantsAutomaticContinue` became
`awaitsContinue` (results settled, hold for the player), the footer shows
下一关 in fire, and `continueToNextStage()` builds the next stage. The order
of bookkeeping changed with it, deliberately: the win is BOOKED the moment
the results settle — run advanced, recordings appended, progress document
written with the completed stage and the next checkpoint — and only the
BUILD of the next stage waits for the tap. Booking first is what makes an
indefinite hold safe: a player who leaves the results page, or whose app
is killed there, keeps the win; under the old order nothing was on disk
until the automatic continue ran. The lab and injected worlds, which have
no next stage and no page to tap, still roll into the same stage again.
Two tests waited on the automatic continue with unbounded loops and hung
(`PersistenceLifecycleTests`' `play`, the campaign-advance integration
test); both now tap 下一关 explicitly and additionally assert the booking
before the tap. GAME_RULES §11.4 is untouched (it fixes the ~3 s to the
results, not what follows); ADR-0011 §4 recorded the automatic continue
and carries the amendment. Not changed: the next stage's card hold (138
ticks, the reference's own 2.3 s) — the transition is now as long as the
player wants it, which is what "长一些" was taken to mean; lengthening the
card itself is the owner's call.

*The results footer (2026-10-08, owner screenshot).* The plates had been
dropped into the statistics row: 重新开始 wrapped to two lines and
MaxHits/MaxCombos wrapped beside it. The footer is now two rows — the
numbers (得分, MaxHits, MaxCombos, 战役完成) on one, the actions centred on
their own under it — and `PlateButtonStyle` fixes every label to one line
(`lineLimit(1).fixedSize()`), so a plate grows to its label and never
folds it.

*Three from one screenshot (2026-10-08, owner).* (1) The reward line
("Reward +330") printed across the 战斗成绩 title: it was a ZStack over the
title; it is now its own line under the title, reserved from the start
when the stage has a clear bonus so the table does not shift, rising into
place when the flow reaches it. (2) The Training Arena's base sat one row
above the bottom border (rows 23–24 over the steel at 26) where every
stage's is flush (24–25); `TrainingArenaFixture` moves it and its brick U
down a row. The M1 `MovementLabFixture` is untouched. (3) The extra-life
pickup has its own voice: `sfx_life_up`, 400 ms, native 8363 Hz — an
original three-step rise G5-D6-G6 (a fifth then a fourth), the top held
with a slow vibrato, a triangle an octave under it for body, levelled at
−18.5 dBFS under the reference's pickup jingle. The owner's reference was
Mario's 1-up chirp; its FUNCTION is taken (a quick rise that lands and
rings), its six-note sequence is not — the standing rule. `GameAudio` maps
`pickupCollected` with `pickupID == "extra_life"` to it and every other
pickup to the reference jingle as before (test added). The set is 26
cues: 19 synthesized, 6 excerpts, the owner's card.

*The arena's base shield hardened nothing (2026-10-08, owner).* A base
shield hardens the stage's `fortTemplate` (GAME_RULES §11.2,
`Stage.activateFort`), and the Training Arena's `StageState` carried none
— the default empty list — so the pickup set the shield timer and
converted no brick. Every one of the twelve stages carries a template (8
cells, the brick U; stage 11's larger fort 24), so the campaign is
unaffected. `TrainingArenaFixture.fortTemplate` is now its brick U, and a
test pins the template to those eight brick cells around the base at
(27, 24). Not added: a content-validator rule that a stage's template
must be non-empty and brick — worth one if a thirteenth stage is ever
authored without it.

*Brick drops — GAME_RULES R5.10, ADR-0023 (2026-10-08, owner).* The owner
asked that breaking brick can randomly drop equipment, chose 3 % per cell
and no difficulty tiers, and left the rest to the proposal: a drop rolls
only when a brick cell's four quadrants are emptied by the PLAYER's round
(quadrant hits, cracks and enemy rounds roll nothing); fort-template
cells and cells over a hidden pickup never roll; a stage cap of 2 after
which nothing rolls; the stage's own drop table minus `extra_life`; and
placement at the legal 2×2 area nearest the cleared cell, spending no
draw. §10.5 is the rule, §12 step 7 names the moment (after the deaths'
drops, cleared cells in (y, x) order, one `drop` draw per cell and a
second only on a hit), §17 item 5 watches for wall farming. Code:
`Combat.applyStrip` notes the cleared cell with the shooter known,
`Stage.rollBrickDrops` rolls, `placePendingPickups` honours
`PendingPickup.preferredCell`; `StageState` carries the chance, cap,
granted count and the tick's cleared cells, all in the checksum and the
invariants; stage JSON takes optional `brickDropChancePermille` /
`brickDropCap` (defaults 30 / 2, so the twelve stages are unchanged),
validated. `ReplayRecording.currentFormatVersion` 12 → 13. The M1
movement golden's checksums did NOT move — the lab fixture has no stage,
and every new checksum field sits under the stage branch — so no golden
was regenerated; the version pin in `ReplayRecordingTests` moved to 13.
`BrickDropTests` (7): full chance drops near the cell, the cap stops
drops and rolls, zero chance still rolls once per cell, an enemy round
drops nothing, fort and hidden cells never roll, an extra life is never a
brick drop, and two seeds agree. Owner-facing: the expected yield per
stage (2–4 hits of which at most 2 land) is in §17 for the playtest.

*The HUD in icons, and the controls in plates (2026-10-08, owner).* The
bar was all text; the owner asked for icons, pointing at 决战坦克 and the
genre, and called the stick and fire buttons ugly. `StageHUDBar` shows
every §15.2 item as the game's own art with a number or pips beside it:
the player's tank and ×N for reserves; the enemy tank (archetype
`normal_a` through the same appearance mapping as the field) with the
number still to come and a dot per tank on the field; the base sprite in
its damage state with the shield icon over it and its durability as pips;
a star and the score; the armour pickup's shield with eight pips; the
special weapon's pickup icon with the rounds left; the power and speed
pickups with three pips each; the equipment's pickup icon or an empty
slot; the invincibility star while it lasts. Icons are cropped to their
drawn content (`MenuArt.glyph`) so the row is art, not canvas padding.
The controls keep their glass (the owner's 2026-10-01 choice) but wear
the plate language: a steel ring for the stick and the normal gun, fire
yellow for the special channel, dark glass inside with a top sheen, the
pressed state filling the glass with the channel's colour; the stick's
base carries the delivery's four arrow glyphs and the held direction
lights; the fire buttons wear the weapon pickups' icons. Hit geometry is
untouched (66 pt visible, 90 pt hit circles 96 pt apart, 96/44 pt stick,
12 pt dead zone, 36 pt leash). Verified on the simulator in a stage and
in the arena. One reading from the gate worth keeping: the smoke render's
arena pass reported ground 21.9 % (it had been 68.6 %), just over its 20 %
floor. Reproduced by hand: a shot 2 s after launch classifies at 0 %, a
shot at 5 s at 68.6 % — the app's first frame now arrives later (one
GameAudio warming 26 cues at the root, under the launch image) and the
script's first retry caught the hand-off mid-fade. A timing margin, not a
rendering defect; if it recurs, the script should wait for two consecutive
playfield classifications rather than accept the first.

*The AP round's weight, and the normal fire button (2026-10-08, owner).*
The AP round in flight is a 4×22 px dart while its pickup draws a 10×24 px
shell, and the owner wanted the round to look like that shell; it now
flies as the pickup's shell, cropped to its art and scaled to about half
a cell wide (`MovementLabScene.heavyShellNode`, 0.7 of the art scale) —
heavier than the normal round's 3×8 px, lighter than the item on the
ground; the trail is unchanged. The normal fire button sampled that 3×8 px
projectile at button size and blurred into blocks, so its face is drawn
in vectors instead (`NormalShellGlyph`): an ogive shell in the round's
own brass with a base band, a highlight and a dark rim, crisp at any
scale. The special button keeps its weapon pickup's icon, which has the
pixels for it. No new art.

## Remaining gaps / follow-up review

Do not interpret green tests as product completion:

- Physical-device legibility, touch occlusion, audio mix and sustained
  performance are unverified (ADR-0006 gate still pending).
- VS-01 keeps the owner-directed reference layout; the plan's "one visible
  Speed or Power pickup" teaching goal is served by carriers and hidden
  treasures, which is a recorded deviation, not equivalence.
- Still deferred: settings, tutorials, accessibility options, the
  input-selection screen (the rest of the former M4 deferral list —
  traversal, ice, foliage, difficulty, mine launch, persistence, pause,
  title — landed on 2026-09-10 late evening; mine launch was later removed
  outright by the R5 consolidation, ADR-0018).
- Reachability validation is a cell flood approximation.
- Owner decisions: none open after 2026-09-10 late evening (invincibility
  A; ADR-0012 answered — brackets by delegation, icons; MaxHits/MaxCombos
  later reinstated by the owner's RC4 draft, GAME_RULES R5 §13; the designed outro and the centred card accepted on the device).
  M3's slice is complete at the owner's acceptance level; M4 (plan §19)
  items 1–5 landed on 2026-09-10 late evening (ADR-0013…0016 proposed):
  campaign progression, screen flow, checkpoint save, difficulty
  profiles and director phases, the deferred mechanics, and — on
  2026-10-03 — the twelve-stage content of §14.1. Remaining M4
  deliverables: settings/accessibility/controller support (owner's item
  6), the external playtest build, the "final replacement visual
  language", performance/export targets, and a PLAYED golden (the chained
  campaign replay is scripted instant wins, not a played run).
