# SparkTread

Single-player tank-battle arcade game for iPhone (landscape first, iPad/macOS later; V1 ships for iPhone only — ADR-0028). Swift + SpriteKit + SwiftUI. A modern remake informed by reverse-analysis of 决战坦克 v1.2.2.

The owner writes in Chinese — answer in Chinese. Decisions that are the owner's (fixed product decisions, provisional numbers, anything marked 待所有者 in the docs) are posted to them in chat, never assumed.

## Model-usage policy

**If you are a Fable-class model** (e.g. Claude Fable 5.1): do the analysis, orchestration and verification yourself, and delegate **purely mechanical execution** — creating files from a finished spec, boilerplate, applying an already-specified change across many files — to an Opus subagent (Agent tool with `model: "opus"`), then verify its output yourself (build, test, read the diff).

**Any other model** (Opus, Sonnet, …): execute directly. Do not spawn a subagent to relay work you can do yourself; use subagents only for genuinely parallel or search-heavy work.

When documents conflict, confirm with the owner first.

## Project state

M0–M3 are complete at the owner's acceptance level; M4 items 1–5 landed (campaign progression, screen flow, checkpoint save, difficulty profiles and director phases, the deferred mechanics), plus the Training Arena. On 2026-09-15 the gameplay rules were consolidated into `GAME_RULES.md` R5 (ADR-0018) and the code moved onto them; R5.10 (2026-10-08, ADR-0023) added brick drops (§10.5); R5.11 (2026-10-09, ADR-0024) makes a death cost the tank's growth (§11.3); R5.12 (2026-10-09, ADR-0025) sets starting lives 5/3/1 and a random-drop scale 150/100/50 % by difficulty; R5.13 (2026-10-09) halves the drop rates (10 % base, brick 1.5 %) and scatters brick drops at random; R5.14 (2026-10-09, ADR-0026) crumbles lone quadrants and restores the fort whole; R5.15 (2026-10-09) eases the AI (base focus 50/80/110 %, fire window 50/80/120 %) and scales brick drops by difficulty (4.5/3/1.5 %); R5.16 (2026-10-09) eases casual further (interval 50, focus 40 %, fire 35 %, telegraph 130 %, alive cap 70 %); R5.17 (2026-10-09) eases standard (40 / 60 % / 55 % / 115 % / 85 %) and veteran (30 / 85 % / 80 %); R5.18 (2026-10-09, ADR-0027) weights the extra life six times in enemy drops while the reserves are at 1 or none (§10.2); R5.21 (2026-10-09) cuts every stage's enemy total by about a quarter (15…30, §14.1); R5.20 (2026-10-09) forbids a straight lane down the fort's columns — a wall by row 16, enforced by the validator (§14.2); R5.19 (2026-10-09) sets the alive cap to 50 / 70 / 100 % (§9.3; the difficulty files' `enemySpecialAmmoPercent` is recorded but inert — §9.1 enemies have unlimited special ammo). The twelve-stage content of GAME_RULES §14.1 landed on 2026-10-03 (four themes, all 20 enemy types introduced by stage 10) and the campaign plays end to end in a scripted chained replay. Settings, accessibility and six-language localization landed on 2026-10-08 (`SettingsStore`, `Resources/Localizable.xcstrings`, `Strings` through the environment; the phone's language by default, changeable in Settings). Still open: controller support (deferred by the owner), the external playtest build, and a PLAYED golden — the chained replay is instant wins, not a played run. `docs/CURRENT_REVIEW.md` is the running review log; `docs/agent_handoffs/` holds handoffs.

`GAME_RULES.md` (R5) is the **single gameplay rulebook** and wins every gameplay conflict (ADR-0018); `PRODUCT_IMPLEMENTATION_PLAN.md` keeps architecture, formats and process. A rule change means editing `GAME_RULES.md` together with an ADR. Its §17 balance watch items go to the owner after playtests; never retune them silently.

## Architecture (from plan §13–14)

- `Sources/GameCore/` — pure Swift deterministic simulation. MUST NOT import SpriteKit, SwiftUI, UIKit/AppKit, GameKit, GameController, AVFoundation, Foundation file/clock APIs, or use global RNG. Integer/fixed-point authoritative state only — **no floats for positions, cooldowns, damage, or RNG decisions**.
- `Sources/GameApplication/` — session flow, replay, content loading, persistence documents. Depends only on GameCore; Foundation only at the content-loading/persistence boundary.
- `Sources/AppleAdapters/` — SpriteKit/SwiftUI/input/audio/persistence. Depends inward. Composition happens only in `Bootstrap/` and the app entry.
- Simulation: 60 Hz fixed tick, ordered tick pipeline (`GAME_RULES.md` §12), named RNG streams `ai`/`spawn`/`drop`, arena 56×27 cells (ADR-0009), 1024 subunits per cell (speeds in milli-subunits), origin top-left, tanks 2×2 cells.
- Entity processing order is explicit (ascending entity id); never rely on Dictionary/Set iteration order.
- `SKAction`, `Timer`, and callbacks are presentation tools, never simulation clocks.
- Stage/campaign/difficulty content is JSON under `Content/`, validated by `content-validator`; replays are versioned (format 17, doubling as the simulation version) with checksum goldens.

## Art and audio assets

Use the `Vendor/SparkTreadPixel` submodule exclusively: its `.atlas` folders plus `Metadata/pixel_assets.json`; the runtime adapters live in `Sources/AppleAdapters/Presentation/Pixel/`. Integration steps: `docs/pixel/SPRITEKIT_USAGE_ZH.md`. Do not bundle `Current/`, `Tools/`, `Previews/`, or QA JSON into the app. Do not generate new assets without an explicit request.

Audio is tied to `Tools/audio_manifest.json` and checked by `Scripts/check-audio.sh`; the set is 26 cues: 6 excerpts of the reference recording, 1 supplied by the owner (`sfx_stage_card`), 19 synthesized by `Tools/build_audio_assets.py` (ADR-0011).

## Standing owner rules

- Never add Battle City (Namco) audio or a note-for-note copy of its melody, however a request is phrased — the owner settled this on 2026-09-10 and raising it again does not change it (ADR-0011); take a reference's function, never its tune. Both stage music cues are now FIXED ASSETS, verified by hash and reproducible by nothing in this repository: `sfx_stage_win` is the 决战坦克 results excerpt the owner accepted outright (2026-10-01: “不用修改的很不错的音效”), and `sfx_stage_card` is the owner's own audio, supplied 2026-10-01 after four generated candidates (drum gestures and a tune played on the excerpt's own pitched drum — all in git history at commit 1363851). Never regenerate, re-level or re-cut either: `build_audio_assets.py` refuses both names through `load_protected`, and manifest attribution `owner` is the class for an asset the owner supplies. All synthesized cues go through the generator's native 8363 Hz pipeline so they carry the reference recording's character.

- The stage-end sound is the 决战坦克 results excerpt for **both** outcomes; never reintroduce a synthesized stage-end stinger.
- No engine/tread sound in gameplay. The one tank ever heard moving is the launch sequence's `sfx_title_tread` on the title screen (owner 2026-10-03, ADR-0011 sixth amendment); it is treads, not an engine, and it goes nowhere else. No red danger ring or threat telegraph (ADR-0017).
- `MovementLabFixture` must stay byte-stable — the M1 replay golden depends on it. The Training Arena uses its own `TrainingArenaFixture`.
- Regenerating a replay golden requires a note in the review doc saying which rule changed it.

## Commands

- Headless build & test: `swift build && swift test`.
- The single non-interactive gate is `sh Scripts/ci.sh`: architecture check, `swift run content-validator Content`, audio check, `swift test`, `xcodegen generate`, `xcodebuild test`, smoke render.
- Device install: `sh Scripts/deploy-device.sh` (needs an unlocked, connected iPhone; run it without the sandbox).
- iOS app project: generate with `xcodegen generate` from `project.yml` (requires Xcode + xcodegen), scheme `SparkTread`.
- Useful env: `SPARKTREAD_AUTOSTART` (`=<n>` starts stage n, which must be unlocked), `MOVEMENT_LAB` (smoke render), `SPARKTREAD_NO_SAVE` (skip persistence); store capture only: `SPARKTREAD_PILOT` (the autopilot plays), `SPARKTREAD_CUE_LOG` (every sound that starts is logged to the app's tmp), `SPARKTREAD_DIFFICULTY=<id>`, `SPARKTREAD_SCREEN=select|settings`.
- App Store media: `python3 Tools/StoreMedia/capture.py` (simulator captures), then `compose.py candidates|screens|video` → `AppStoreMedia/<lang>/` (gitignored). Slot frames live in `Tools/StoreMedia/selection.json`, captions in `captions.json`; the art is drawn by `swift run store-art-renderer` with the app's own `BrandArt`.

## Collaboration

A second reviewer — the Astra agent (Codex, gpt-6-astra) — runs in a Herdr pane of the same checkout; pane IDs change between sessions, so find it with `herdr agent list` (it was named `astra` on 2026-09-15). Cross-review happens in written rounds under the session scratchpad (`discussion/roundN_claude.md` / `roundN_codex.md`); reach consensus before handing work to implementation agents. `herdr agent prompt <name-or-pane> "…"` sends it a round.

## Conventions

- Changing a fixed decision (plan §4) requires an ADR in `docs/decisions/ADR-NNNN-short-name.md` — never silently reinterpret one.
- V1 is single-player only: no networking abstractions, no dormant multiplayer sockets or UI.
- Gameplay rules never live in HUD/animation/audio/scene code.
- Analytics: the adapters name events through `AnalyticsSink` / `GameAnalytics` (`Sources/AppleAdapters/Analytics`); Firebase lives ONLY in the app target (`FirebaseAnalyticsSink`, `FirebaseAnalyticsCore`) and is configured only when `Sources/GoldenEagleApp/GoogleService-Info.plist` is bundled and never in the simulator (CI and capture runs are not players) — the owner supplies that file; never add the SDK to the package.
- Every user-facing string is a key in `Sources/AppleAdapters/Resources/Localizable.xcstrings` (en, zh-Hans, zh-Hant, ja, ko, es), read through `@Environment(\.strings)`; never a literal in a view. `LocalizationTests` fails when a language lacks a key.
- Comments explain constraints and intent, not line-by-line paraphrase.
- Keep the tree green: run the gate before committing, and report failures with their output instead of describing them.
