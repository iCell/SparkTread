# ADR-0013: Campaign Progression and the Carried Session State

Status: Proposed (drafted 2026-09-10 late evening on the owner's instruction to complete M4 items 1–5; the owner's content direction for the stages — "按照原来地图，但是适配新的屏幕比例，允许你在原版基础上按照你认为最合适的方式自由发挥" — is applied)

Date: 2026-09-10

Related: plan §5.1, §6.4–6.5, §11.3–11.4, §12.1, §16.2–16.3, §19 M4; ADR-0011 §4 (the provisional same-stage loop this replaces); ADR-0012 (clear bonuses, `stageNumber`); `GAME_RULES.md` §3.1 (reference stage roster)

## Context

M3 ended with one stage that, once won, replayed itself (ADR-0011 §4:
"a provisional prototype loop, not campaign progression"). M4 (plan §19)
requires VS-01…VS-03, a three-stage run that is "complete, restartable,
and save-safe", and "the campaign-spanning three-stage replay … using
chained `initial_session_state` headers" (§16.3: a campaign replay is an
ordered list of stage replays; "each stage's exit state equals the next
stage's `initial_session_state`"). The plan defines the carried state as
"per-player carried upgrades/ammo/lives and campaign checkpoint hash"
(§16.3) and resets armor on every spawn (§6.5); it leaves open the
post-win flow (§12.1 "Next Stage / Retry / Exit" vs the reference's
automatic next card), retry semantics under carry-over, score carry and a
continue after game over (§24 Q5, explicitly not to be guessed).

The owner asked for the second and third stages to follow the reference
game's maps adapted to the 56×27 arena, with freedom to adjust. The
reference's stage 2 ("Hidden in Grass": water channels, grass cover,
brick blocks, steel plates) and stage 3 (open sand with steel
staircases) were read from the owner's recording at play start
(`Tools/reference_measure/results_screens.py` frames) and re-drawn for
the arena; enemy compositions were chosen to exercise the families the
reference's results screens showed for those stages (VS-02: Normal,
Rapid, Fire; VS-03: Normal, Rapid, Explosion, AP).

## Decision

1. **Campaign content.** `Content/campaigns/campaign_v1.json` lists the
   ordered stage ids; `CampaignValidator` requires every listed stage to
   exist and to carry `stageNumber == position` (ADR-0012 tiers and the
   card title agree with the order). The content validator tool checks
   campaigns against the stages; the ID registry gains an optional
   `campaigns` category. Stage ids follow the reference maps
   (`frontier_02_hidden_in_grass`, `frontier_03_desert_stairs`) and
   replace the registry's seeded placeholders (`floodplain_02_…`,
   `iron_citadel_03_…`, never released); all three stages use the one
   slice theme (plan §3.2, §11.4 Frontier 1–3).
2. **`SessionState`** (GameApplication) is the carried per-player state:
   lives, score, special ammunition per weapon, and the retained speed,
   power, equipment and special weapon. `carried(from:)` reads a world's
   player at the deciding tick (upgrades from the live tank when it
   exists); `StageBuilder.build(_:rules:session:)` applies it to the
   fresh player and its first tank; armor is the stage's (§6.5). The
   builder and the loaders refuse an out-of-domain state before a world
   exists. A won stage's exit state includes the ADR-0012 bonuses.
3. **`CampaignRun`** holds the campaign, the stage index and the
   CHECKPOINT: the session state at the current stage's start.
   `advance(exitState:)` records the win and moves on with the exit state
   as the new checkpoint; the last stage completes the run.
4. **Flow (decided here, provisional until the owner amends):** a won
   stage advances automatically into the next stage's card (the reference
   behaviour the owner accepted on the device), carrying the exit state;
   a lost stage offers "重新开始", which rebuilds the SAME stage from its
   checkpoint (nothing from the failed attempt survives; no life or score
   cost); the last stage's results show "战役完成" and "再来一局" (the
   campaign from stage 1 with the campaign-start state). No continue with
   reset score exists (§24 Q5 stays open); exit to a title screen is the
   screen-flow work that follows.
5. **Replay format 4.** `ReplayRecording` carries `stageID` and
   `sessionState` in its header; `ReplayPlayer.replay` refuses a header
   whose state is out of domain or does not describe the initial world's
   player. `CampaignReplay` is the ordered list of stage recordings;
   `ReplayPlayer.replayCampaign` replays each stage for its recorded tick
   span, requires an outcome, and requires the next header to equal the
   previous stage's exit state (`sessionStateChainBroken` otherwise). The
   controller keeps the completed stages' recordings as the run's
   campaign replay.
6. **Controller.** `MovementLabController` walks a `CampaignRun` through a
   `StageProvider` (the bundle in the app; a closure in tests); the
   lab and injected worlds keep their old behaviour. `stageID` comes from
   the run (the card title parses its number and name).

## Consequences

- Format 3 recordings are refused (`unsupportedFormat(3)`); the M1 movement
  golden (a lab world, no stage) is unchanged.
- The three-stage chained replay in the tests uses the real stages won at
  once (empty spawn queues) to prove the chain machinery; a golden of a
  played three-stage run waits for a scripted or recorded solution.
- The app needs the campaign in its bundle (`project.yml` copies
  `Content/campaigns`); a missing or invalid campaign is a build error.
- Open for the owner: the post-win automatic advance vs a "下一关" choice;
  a continue after game over; whether Retry should cost a life or score.
