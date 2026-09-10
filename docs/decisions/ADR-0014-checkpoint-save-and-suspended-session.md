# ADR-0014: Checkpoint Save and the Suspended Session

Status: Proposed (drafted 2026-09-10 late evening, M4 item 3)

Date: 2026-09-10

Related: plan §5.1, §13.2, §13.3, §16.1–16.3, §17.5, §18.1; ADR-0003 (serializable world state, suspended snapshot), ADR-0007 (explicit pause/resume), ADR-0013 (campaign run, session state)

## Context

Plan §16.1 names the files (`campaign_progress.json`,
`suspended_session.json`; every file versioned, written atomically,
migrations tested), §16.2 what progress holds, ADR-0003 §3 what the
suspended session holds (a mid-stage authoritative snapshot plus the
command log, written when the app leaves the foreground mid-stage,
validated on load, deleted on stage completion or abandonment) and §17.5
the resume offer on cold launch ("declining discards it"). §13.2 places
the persistence operations' definition in session orchestration and their
implementation in an adapter. Left open: what a resume shows first (the
intro/outro are presentation), how a broken or foreign file is treated,
and where the files live.

## Decision

1. **Documents (GameApplication, Codable, versioned).** `CampaignProgress`
   {campaign id, completed stage ids, the checkpoint `CampaignRun` to
   continue from (nil once complete), best score}; `SuspendedSession`
   {the `CampaignRun`, the `WorldState` snapshot, the `ReplayRecording` so
   far}. Both carry `schemaVersion`; `SaveSchema.check` refuses any
   version but the current one (1) — the version-to-version migration
   table starts empty and grows with the first change. Every document
   validates itself before it is written or trusted: a snapshot must be
   of a stage still being played, of the run's stage, with a recording
   that starts where it says, precedes the world and matches the
   checkpoint header.
2. **Operations.** `CampaignPersistence` (GameApplication protocol):
   load/save progress, load/save/clear the suspended session.
   `InMemorySaveStore` for tests; `FileSaveStore` (AppleAdapters) writes
   sorted JSON atomically under `<Application Support>/SparkTread/`, reads
   the version FIRST and gates it before decoding, and reports an
   unreadable or foreign file as an error (the file stays for
   inspection). No iCloud or backup policy is decided.
3. **When.** Progress is checkpointed after every completed stage
   (§5.1) with the next stage's run as the checkpoint (none after the
   last stage). The snapshot is written by
   `applicationDidBecomeInactive()` when a campaign stage is being
   played (never in the lab, an intro, an outro or the results), before
   the clock stops; it is cleared the moment a stage is decided, on
   abandonment (返回标题), and when the player declines it on the title.
4. **Resume.** The title offers "继续上次战斗" when a snapshot exists (and
   "继续战役" when only a checkpoint does). Resuming builds the session
   from the snapshot's world with its recording — the resumed run replays
   as ONE recording from the stage start — skips the intro (already
   seen; presentation state is not restored) and opens PAUSED so the
   player resumes deliberately with a fresh clock (ADR-0007).
5. **Failures never interrupt play.** A store that fails to write is
   recorded on the controller (`persistenceFailure`) and shown as a
   notice on the title; a store that fails to open leaves the game
   playable without saves.

## Consequences

- Required tests (plan §18.1, ADR-0003): snapshot → restore → resume
  equals an uninterrupted run, checksum for checksum, at the session and
  controller levels; the controller writes on inactivity mid-play only,
  clears on decision and abandonment, checkpoints on a win; the file
  store round-trips, gates versions and reports corruption; migrations
  are exercised by the version gate until a second version exists.
- `SPARKTREAD_NO_SAVE=1` disables the store (automation).
- Open for the owner: whether resuming should replay the intro card;
  whether a declined snapshot should survive one more launch; backup and
  iCloud policy.
