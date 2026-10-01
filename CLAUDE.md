# SparkTread

Single-player tank-battle arcade game for iPhone (landscape first, iPad/macOS later). Swift + SpriteKit + SwiftUI. A modern remake informed by reverse-analysis of 决战坦克 v1.2.2.

The owner writes in Chinese — answer in Chinese. Decisions that are the owner's (fixed product decisions, provisional numbers, anything marked 待所有者 in the docs) are posted to them in chat, never assumed.

## Model-usage policy

**If you are a Fable-class model** (e.g. Claude Fable 5.1): do the analysis, orchestration and verification yourself, and delegate **purely mechanical execution** — creating files from a finished spec, boilerplate, applying an already-specified change across many files — to an Opus subagent (Agent tool with `model: "opus"`), then verify its output yourself (build, test, read the diff).

**Any other model** (Opus, Sonnet, …): execute directly. Do not spawn a subagent to relay work you can do yourself; use subagents only for genuinely parallel or search-heavy work.

When documents conflict, confirm with the owner first.

## Project state

M0–M3 are complete at the owner's acceptance level; M4 items 1–5 landed (campaign progression, screen flow, checkpoint save, difficulty profiles and director phases, the deferred mechanics), plus the Training Arena. On 2026-09-15 the gameplay rules were consolidated into `GAME_RULES.md` R5 (ADR-0018) and the code moved onto them. Still open: the twelve-stage content (only three stages exist), settings/accessibility/controller support, the external playtest build, the played three-stage golden. `docs/CURRENT_REVIEW.md` is the running review log; `docs/agent_handoffs/` holds handoffs.

`GAME_RULES.md` (R5) is the **single gameplay rulebook** and wins every gameplay conflict (ADR-0018); `PRODUCT_IMPLEMENTATION_PLAN.md` keeps architecture, formats and process. A rule change means editing `GAME_RULES.md` together with an ADR. Its §17 balance watch items go to the owner after playtests; never retune them silently.

## Architecture (from plan §13–14)

- `Sources/GameCore/` — pure Swift deterministic simulation. MUST NOT import SpriteKit, SwiftUI, UIKit/AppKit, GameKit, GameController, AVFoundation, Foundation file/clock APIs, or use global RNG. Integer/fixed-point authoritative state only — **no floats for positions, cooldowns, damage, or RNG decisions**.
- `Sources/GameApplication/` — session flow, replay, content loading, persistence documents. Depends only on GameCore; Foundation only at the content-loading/persistence boundary.
- `Sources/AppleAdapters/` — SpriteKit/SwiftUI/input/audio/persistence. Depends inward. Composition happens only in `Bootstrap/` and the app entry.
- Simulation: 60 Hz fixed tick, ordered tick pipeline (`GAME_RULES.md` §12), named RNG streams `ai`/`spawn`/`drop`, arena 56×27 cells (ADR-0009), 1024 subunits per cell (speeds in milli-subunits), origin top-left, tanks 2×2 cells.
- Entity processing order is explicit (ascending entity id); never rely on Dictionary/Set iteration order.
- `SKAction`, `Timer`, and callbacks are presentation tools, never simulation clocks.
- Stage/campaign/difficulty content is JSON under `Content/`, validated by `content-validator`; replays are versioned (format 12, doubling as the simulation version) with checksum goldens.

## Art and audio assets

Use the `Vendor/SparkTreadPixel` submodule exclusively: its `.atlas` folders plus `Metadata/pixel_assets.json`; the runtime adapters live in `Sources/AppleAdapters/Presentation/Pixel/`. Integration steps: `docs/pixel/SPRITEKIT_USAGE_ZH.md`. Do not bundle `Current/`, `Tools/`, `Previews/`, or QA JSON into the app. Do not generate new assets without an explicit request.

Audio is tied to `Tools/audio_manifest.json` and checked by `Scripts/check-audio.sh`; seven of the 24 cues are excerpts of the reference recording, the rest are synthesized by `Tools/build_audio_assets.py` (ADR-0011).

## Standing owner rules

- Never add Battle City (Namco) audio or a note-for-note copy of its melody. The stage-end cue `sfx_stage_win` is finished — the owner accepted it outright (2026-10-01: “不用修改的很不错的音效”) — so never regenerate, re-level or re-cut it. The opening cue (`sfx_stage_card`) is re-sequenced from that excerpt's own drum strokes and must stay a set with it: same kit, same room bed, the measured ≈127 bpm sixteenth grid, the excerpt's own RMS, no step ever at digital silence. But it is an opening GESTURE, never a loop or a groove (owner 2026-10-01: three successive grooves were “非常不合适” as opening music, including one that matched the stage end on every measurement), and it carries a TUNE (owner 2026-10-01, pointing at the Battle City NES start theme for the function): an original figure in C minor pentatonic played by resampling the excerpt's own most cleanly pitched drum slice, over kicks and ticks, into a crash landing where the intro hands over to play. Battle City's melody is never copied or paraphrased, however the request is phrased — the owner settled this on 2026-09-10 (ADR-0011) and asking again does not change it; take only the function, write the notes. Never make the card the stage end's own passage and never compose it from synthesized instruments — the tune is played on the recording's own drum, which is what keeps both rules true at once. `SHAPE` in the generator's stage-card block holds the owner's choice (`melodic` ships; `roll_hit`, `three_strikes` and `crescendo` are the auditioned drum-only shapes). All synthesized cues go through the generator's native 8363 Hz pipeline so they carry the reference recording's character.
- The stage-end sound is the 决战坦克 results excerpt for **both** outcomes; never reintroduce a synthesized stage-end stinger.
- No engine/tread sound. No red danger ring or threat telegraph (ADR-0017).
- `MovementLabFixture` must stay byte-stable — the M1 replay golden depends on it. The Training Arena uses its own `TrainingArenaFixture`.
- Regenerating a replay golden requires a note in the review doc saying which rule changed it.

## Commands

- Headless build & test: `swift build && swift test`.
- The single non-interactive gate is `sh Scripts/ci.sh`: architecture check, `swift run content-validator Content`, audio check, `swift test`, `xcodegen generate`, `xcodebuild test`, smoke render.
- Device install: `sh Scripts/deploy-device.sh` (needs an unlocked, connected iPhone; run it without the sandbox).
- iOS app project: generate with `xcodegen generate` from `project.yml` (requires Xcode + xcodegen), scheme `SparkTread`.
- Useful env: `SPARKTREAD_AUTOSTART`, `MOVEMENT_LAB` (smoke render), `SPARKTREAD_NO_SAVE` (skip persistence).

## Collaboration

A second reviewer — the Astra agent (Codex, gpt-6-astra) — runs in a Herdr pane of the same checkout; pane IDs change between sessions, so find it with `herdr agent list` (it was named `astra` on 2026-09-15). Cross-review happens in written rounds under the session scratchpad (`discussion/roundN_claude.md` / `roundN_codex.md`); reach consensus before handing work to implementation agents. `herdr agent prompt <name-or-pane> "…"` sends it a round.

## Conventions

- Changing a fixed decision (plan §4) requires an ADR in `docs/decisions/ADR-NNNN-short-name.md` — never silently reinterpret one.
- V1 is single-player only: no networking abstractions, no dormant multiplayer sockets or UI.
- Gameplay rules never live in HUD/animation/audio/scene code.
- Comments explain constraints and intent, not line-by-line paraphrase.
- Keep the tree green: run the gate before committing, and report failures with their output instead of describing them.
