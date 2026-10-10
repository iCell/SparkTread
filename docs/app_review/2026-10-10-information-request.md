# App Review information request — 0.1.0, 2026-10-10

App Review asked for six things (limited review history for the account). Items
2–5 are settled and reproduced verbatim below; item 1 is a recording only the
owner can make; item 6 waits on an owner decision (see the end).

Apple asks for this text in two places: the Resolution Center reply **and** the
App Review Information → Notes field. `fastlane/metadata/review_information/
notes.txt` is the source for the Notes field; keep the two identical.

---

## 2. Purpose and target audience

> SparkTread is a single-player arcade game — an original, modern take on the
> top-down tank-defence format of early coin-op and console arcade games. The
> player drives one tank inside a walled arena, destroys the enemy tanks that
> roll in, and keeps them from reaching the base at the bottom of the field.
>
> It is entertainment rather than a utility. The gap it fills: the arcade
> tank-battle format is widely remembered, but on iPhone it is served mostly by
> ad-driven clones and emulator-style on-screen D-pads. SparkTread is built for
> touch from the ground up — a two-thumb control scheme designed for the phone,
> a twelve-stage campaign with a tuned difficulty curve, three difficulty
> levels, and no advertising and no in-app purchases of any kind.
>
> Target audience: players aged 9 and up who enjoy short-session retro arcade
> games. The app is rated 9+ for frequent cartoon or fantasy violence (pixel-art
> tanks firing at pixel-art tanks; no blood, no human figures, no gore).

## 3. Setting up and accessing the main features

> No account, no login, no credentials, no sample files and nothing to purchase.
> Every feature is reachable on a fresh install, offline, within seconds:
>
> - Launch the app → title screen → **Start Game** → choose **Casual**,
>   **Standard** or **Veteran** → a stage card appears → stage 1 begins.
> - Controls are landscape, two thumbs: the left thumb is a four-way movement
>   pad, the right thumb fires. There is nothing else to learn.
> - Objective: destroy every enemy tank in the stage while keeping your own base
>   (the eagle at the bottom of the arena) intact and your lives above zero.
> - Stages unlock in sequence as they are cleared. Progress saves automatically;
>   **Continue** on the title screen resumes the campaign, and **Resume Battle**
>   returns to a stage that was interrupted.
> - **Training Arena** (title screen): a free-play arena for trying the weapons
>   and terrain without losing lives.
> - **Settings** (title screen): sound volume, haptics, interface language
>   (English, 简体中文, 繁體中文, 日本語, 한국어, Español — the device language by
>   default), mirrored controls, high contrast, larger HUD, reduced motion, and
>   a Feedback button that opens the reviewer's own mail app with a prefilled
>   diagnostics footer. Nothing is sent unless the user sends it.
>
> Fastest path for a reviewer: choose **Casual**. It grants five lives, the
> slowest enemy decisions and the most frequent pick-ups, so a full stage can be
> cleared in about two minutes.

## 4. External services, tools and platforms

> Google Firebase Analytics (Google LLC) is the only external service the app
> contacts. It receives aggregate gameplay events — stage started, stage
> cleared, stage failed, campaign completed — each carrying the stage number and
> id, the chosen difficulty, the score and the lives remaining, plus Firebase's
> own standard technical context (a random app-instance identifier, device
> model, OS version, app version, language, approximate region).
>
> There is no advertising identifier (IDFA) and no ad network, no tracking
> across apps or websites, no third-party login or authentication service, no
> payment processor, no in-app purchase, no AI or machine-learning service, no
> external data provider, and no server operated by the developer.
>
> Everything that produces the game — simulation, rendering, audio, input and
> saved progress — runs on the device using Apple frameworks (SpriteKit,
> SwiftUI, AVFoundation, UserDefaults). The app is fully playable in Airplane
> Mode; the network is used only to deliver the analytics events above.

## 5. Regional differences

> None. The app ships identical features and identical content in every region.
> The only region-dependent behaviour is the interface language, which follows
> the device setting across the six supported languages and can be overridden in
> Settings. There is no region-locked content, no regional server, no
> geographically gated feature, and no difference in gameplay, pricing model or
> available modes between storefronts.

---

## 1. Screen recording — owner action

Apple wants a recording **captured on a physical device running the latest OS**,
beginning with the app launch and showing the typical user flow. None of the
conditional items apply: the app has no account flow, no user-generated content
and no paid content.

Install build **0.1.0 (1)** from TestFlight on the iPhone (the submitted build),
then record with iOS Screen Recording (Settings → Control Center → add Screen
Recording; swipe down, tap the record button, wait for the countdown, launch the
app). Alternatively connect the iPhone by cable and use QuickTime Player → File
→ New Movie Recording → choose the iPhone as the source.

Suggested run, about two and a half minutes, Casual difficulty:

| time | what to show |
|---|---|
| 0:00 | Home screen, tap the SparkTread icon — the launch must be in frame |
| 0:05 | Title screen: let the tread animation play, show the menu |
| 0:12 | Tap **Start Game** → difficulty screen → choose **Casual** |
| 0:20 | Stage card, then stage 1 begins |
| 0:25 | Drive with the left thumb, fire with the right — destroy two or three tanks |
| 0:50 | Shoot through a brick wall to open a lane; show the base at the bottom |
| 1:05 | Collect a pick-up and fire the changed weapon |
| 1:25 | Clear the stage — show the results screen and the next stage card |
| 1:45 | Pause, return to the title screen |
| 1:55 | **Training Arena** — a few seconds of free play |
| 2:10 | **Settings** — scroll the whole list: language, accessibility, feedback |
| 2:25 | Switch the language once to show it apply live, then stop |

Upload the file with the Resolution Center reply.

---

## 6. Regulated industry and protected third-party material

The owner chose on 2026-10-10 to hold no third-party material rather than
disclose unlicensed audio: the six excerpts of the 决战坦克 recording and the
shot derived from one of them were synthesized from the same measurements, at
the same durations and levels (ADR-0029). `Scripts/check-audio.sh` now reports
*0 excerpts*. The answer is therefore:

> SparkTread does not operate in a regulated industry, and the app contains no
> protected third-party material. Everything in it is the developer's own work:
> the source code; the pixel art, drawn for this app; the stage layouts; and the
> audio, which is synthesized by a generator committed in the project's own
> repository, with a single cue supplied by the developer. No third-party brand,
> logo, trademark, recording or licensed asset appears anywhere in the app, and
> the app displays no third-party content at runtime. There is no account, no
> user-generated content and no external content feed, so nothing a reviewer
> sees originates outside the app bundle.

Because the audio changed, **0.1.0 (1) is not the build this reply describes**:
a new build is archived and uploaded, and the reply goes out against it.

Still outstanding: the owner has not auditioned the seven replacements. Their
levels are verified by measurement — each lands at its predecessor's duration
and RMS — but their character is new.
