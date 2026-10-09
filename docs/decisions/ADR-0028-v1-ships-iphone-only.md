# ADR-0028: Version 1 ships for iPhone only

Status: Accepted (owner decision, 2026-10-09)
Date: 2026-10-09
Related: PRODUCT_IMPLEMENTATION_PLAN §1, §1.6, §11 (presentation), §19 (release checklist); ADR-0009 (universal arena), ADR-0022 (fullscreen arena)

## Context

Preparing the App Store media showed what the app looks like on a 13-inch
iPad: the title and menu backdrop is a fixed 1024×512 field with black
around it (it is the launch image's field, sized to cover every iPhone),
and the 56×27 arena, fitted to the iPad's 4:3 width, sits in a band with
tall steel strips above and below, so tanks read small. The plan lists
iPad as the first secondary target, and its V1 scope says gameplay
"supports landscape orientation on iPhone and iPad". The project shipped
`TARGETED_DEVICE_FAMILY` "1,2", which would make 13-inch iPad screenshots
mandatory and put the iPad presentation in front of App Review. The owner
decided: "第一版本只支持 iPhone".

## Decision

1. The V1 app target MUST declare `TARGETED_DEVICE_FAMILY` "1" (iPhone);
   the iPad-only Info.plist keys are removed.
2. V1 App Store media are iPhone only (6.9-inch screenshots and the
   1920×886 preview). The store-media tooling keeps its iPad layout for a
   later version but does not produce iPad files.
3. iPad remains the first secondary target (plan §1). Making it a target
   again needs: a backdrop that covers 4:3 (the launch image and the title
   share one field), the intro's drive measured for the wider screen, and
   the arena band's presentation reviewed with the owner.
4. Layout code and its tests for iPad point sizes stay: an iPhone-only app
   still runs on iPad in iPhone compatibility mode, and the arena must
   remain correct there.

## Alternatives considered

- Fix the iPad presentation before V1: delays the first release for a
  secondary target.
- Ship "1,2" with the current iPad presentation: the black-bordered menus
  and the small arena would be the iPad store page and the review device.

## Gameplay consequences

None. On iPad the App Store offers the app as an iPhone app (scaled), as
for every iPhone-only app.

## Architecture consequences

Project configuration only (`project.yml`). No code path changes.

## Migration cost

None for saves or replays. Plan text that put iPad in V1 points here.

## Tests affected

None; `ArenaLayoutTests` keeps its iPad sizes (compatibility mode).
