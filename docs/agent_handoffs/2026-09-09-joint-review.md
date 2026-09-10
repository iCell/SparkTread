# Handoff: joint review 2026-09-09/10 — combat contract, lifecycle, presentation, reference audio, stage transitions

Date: 2026-09-10 (started 2026-09-09)  
From → To: Claude (Fable 5.1) with PI (gpt-6-astra) as reviewer → next session  
Scope: M3 hardening across GameCore combat/stage/navigation rules,
GameApplication replay/session/stage flow/content admission, AppleAdapters
lifecycle/input/audio/presentation, the candidate reference-derived sound
set and the measurement record

## State of the work

- DONE and verified by Claude's gates: everything listed in
  `docs/CURRENT_REVIEW.md` ("Corrections made in the joint review",
  "Owner-directed changes", "Reference audio and transitions"). Proof:
  `swift test` (dated count in "How to verify"), simulator tests on
  iPhone 17 (Claude's runs only — not PI acceptance), architecture check,
  content validator, audio check, `git diff --check`.
- Jointly closed at engineering scope: rounds 1–7 (combat/replay/input/
  audio lifecycle), 8–9 (drops, navigation, replay format 3), 10–14
  (candidate sound set, stage transitions, effect clock, input admission).
  Round 15 (whole-tree pre-commit pass) raised R15-01…09; their disposition
  is recorded in `docs/CURRENT_REVIEW.md` "Joint review status". Scoped
  sign-offs only — device, audition/rights and product-completion gates
  remain open.
- IN PROGRESS: nothing mid-edit. All changes are in the working tree,
  uncommitted (the owner has not asked for a commit). `git status --short`
  collapses `Sources/AppleAdapters/Resources/` and `Tools/reference_measure/`
  into single entries; count the expanded inventory with
  `git status --short -uall` before staging (98 paths after round 16 — a
  snapshot, not a maintained total). Never stage research media, virtual
  environments, caches or scratch outputs.
- CANDIDATE, not accepted: the reference-derived sound set (ADR-0011,
  proposed) — pending the owner's audition, a recorded provenance/rights
  review and a rerun of the measurement record. ADR-0010 acceptance and
  M4 items are not started.

## Decisions made

- ADR-0010 (PROPOSED, not accepted): special-channel fallback, fort-ring
  hardening + occupied-cell skip, restoration mapping as a ruleset flag
  (default off), hidden-treasure reveal predicate, mine visibility.
- Local, reversible: keyboard fire bindings J/U (normal) and K/I (special),
  controller A (normal) B/X (special); dry-fire audio throttle 0.35 s; stall
  threshold = six ticks of raw elapsed time; effect pool 48, scorch pool 24;
  enemy-mine cloaking alphas 0 / 0.3 / 0.55, player floor 0.6.
- Local, reversible: `sfx_base_own_hit` is a synthesized placeholder for the
  ADR-0005 own-fire cue (still the 2026-09-09 provisional voice; the
  reference recording has no own-fire cue).
- ADR-0011 (PROPOSED, not accepted): re-synthesis as the candidate
  production method, event mapping, displacement-driven engine
  (provisional), `StageFlow` timeline, tally-derived results; no reward
  rule.
- Results-panel layout policy: rows scroll inside a panel bounded to half
  the surface height; the restart button stays outside the scroll. Not
  verified on a device with more than two archetype rows.

## How to verify

```sh
sh Scripts/check-architecture.sh
swift run content-validator Content
sh Scripts/check-audio.sh selftest   # corruption / builder-refusal cases on temp copies
sh Scripts/check-audio.sh       # synthesized WAVs == generator; excerpts' hashes + extractor hash == manifest (re-extracted and metadata-compared if SPARKTREAD_REFERENCE_WAV is set)
sh Scripts/smoke-render.sh selftest   # classifier + failure-path checks, no simulator
sh Scripts/smoke-render.sh      # simulator: the SKView actually presents the PLAYFIELD (terrain occupancy, stage + lab); needs ffmpeg
swift test                      # 2026-09-10 evening after ADR-0012: 258 tests / 63 suites (Claude's run; PI was unavailable)
xcodegen generate && xcodebuild test -project SparkTread.xcodeproj -scheme SparkTread \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .build/DerivedData
python3 Tools/build_audio_assets.py   # regenerates the SYNTHESIZED voices and their manifest entries; originals are untouched
SPARKTREAD_REFERENCE_WAV=… python3 Tools/extract_reference_audio.py   # re-cuts the eight excerpts from the pinned recording (sha256 df9ad477…)
```

## Landmines

- `DomainEvent` payload shapes changed (owner identity, positions, impact
  kinds, `baseDamaged.allied`); pattern matches must use the new arity.
  Position anchors are documented on the enum — tank events are top-left,
  projectile events are box centers, pickups are cell centers.
- Checksum surface: `BaseState.fortRingRestore`/`burnCooldownTicks`,
  `ProjectileState.hitTankIDs`, `FireHazardState.ownerEntityID`. Changing any
  of them moves goldens; regenerate only with a stated reason.
- `WorldInvariants` now requires EXACT equality of stored active counts and
  live entities; any new spawn/removal path must go through the
  count-adjusting helpers (`removeProjectile`, `decrementActiveCount`).
- `PickupRuleset` must be validated at the boundary; `MovementLabSession`
  preconditions it. Every pickup creation path takes `rules:`.
- `ReplayRecording` format 3 is self-contained; do not reintroduce a
  fixture-seeded player. Debug hooks rebase the recording. Any change to
  rules shape OR simulation behaviour bumps the format (old recordings are
  rejected, never replayed into a different game).
- Presentation must never infer positions from the current world for
  events (entities may be gone within a drain).
- Audio content (owner's creative decision 2026-09-10): eight files are
  EXCERPTS of the reference recording owned by
  `Tools/extract_reference_audio.py` (manifest attribution `excerpt`); the
  generator refuses those names before writing anything. The rest is the
  CANDIDATE synthesized set (ADR-0011, accepted 2026-09-10). The owner
  recorded the rights decision on 2026-09-10 (accepts the excerpts, the
  synthesized voices and the original jingle; no third-party licence is
  held) — the agents record it, they do not vet it. The confirmed and uncertain voices follow the
  measurements recorded in `docs/CURRENT_REVIEW.md` (change those numbers
  with a new measurement or an audition decision, and say which in the
  builder comment); the derived and invented variants are design choices
  and tuning after audition is expected. `Tools/audio_manifest.json`
  records every file's hash and attribution; `Scripts/check-audio.sh` fails
  when the generator and the bundled files or the manifest disagree.
  Extracted reference audio never enters the repository without an owner
  rights record.
- `WorldInvariants` checks every entity id and id reference against
  `1..<nextEntityID` before any arithmetic; `StageValidator` enforces the
  stage budget (`maxEnemiesPerStage`) and the world's timer/cap domains;
  `MovementLabSession` preconditions all three rulesets and offers a
  throwing `make(...)` for data-driven configurations.
- The stage-start jingle is an ORIGINAL composition in the idiom of NES
  Battle City's (Namco's) stage start; never replace it with an excerpt of
  that jingle or a note-for-note re-creation of its melody.
- Stage transitions are `StageFlow` (GameApplication): a pure tick
  timeline the controller advances; the simulation steps only while
  `allowsSimulation`. Presentation reads phase/progress; it never drives
  the timeline. Outcome stingers are flow cues, not event sounds.
- Input admission is ONE policy (`MovementLabController.syncInputAdmission`):
  accepted only while the clock runs AND the flow is in play; every
  transition releases held/pending input and advances the reset watermark.
  Do not add a second gate elsewhere.
- Transient scene effects age on `MovementLabScene.presentationTime`
  (frame deltas), never on `world.tick` — the world holds during cutscenes.
- NEVER present the scene through `SpriteView(scene:isPaused:)`: bound to
  the scene phase it left the SKView blank on device and simulator
  (2026-09-10). Pause the SCENE (`scene.isPaused`) on inactivity instead.
- There is NO engine/tread sound by owner decision (2026-09-10); do not
  reintroduce one without a new owner decision.
- Results capacity comes from `KillTally` at `beginOutro(won:resultRows:)`;
  never cap rows in the view.
- Injected worlds restart from themselves (`injectedWorld`); the bundled
  stage is only loaded when no world was injected.

## Suggested commit split (PI, round 15; the owner decides)

1. Core/content contracts: combat, navigation, rules, invariants, stage
   validator/builder, replay schema boundary, and their tests.
2. Adapter input/lifecycle/presentation fixes and the integration tests.
3. Stage orchestration (`StageFlow`, `KillTally`, controller/scene/view)
   with the candidate audio generator, resources, manifest and ADR-0011.
4. Measurement tooling (`Tools/reference_measure/`, `Scripts/check-audio.sh`)
   and the consolidated review/handoff documentation.

Shared files may need hunk staging; never leave an intermediate revision
that does not compile, and never stage research media, virtual
environments or caches.

## Next steps

1. Owner: look at the designed outro on the device (stamped title with
   flash/shake, closing curtain, centred results card with tank icons;
   the reward text rises over the card title on a win) and the stage-end
   passage on both outcomes. Decided already: invincibility stays 10 s;
   ADR-0012 accepted (brackets by delegation, no MaxHits/MaxCombos,
   icons). Every stage JSON needs `stageNumber`; the HUD score is paced
   during the outro (`controller.hud.score` vs the world's score).
2. When PI is back (usage limit, ≈5 days from 2026-09-10): hand it
   rounds 28+ — the jingle revision, the owner's decisions, ADR-0012,
   the icons/panel and the stinger removal — for its own probes.
3. Physical-device pass (ADR-0006 gate): legibility, touch occlusion, HUD
   fit, audio mix; large-results-panel layout.
4. M4 work per plan §19 (VS-02/VS-03, traversal, difficulty, lifecycle
   persistence, settings).
