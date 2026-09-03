# Handoff: <work package / task id> — <one-line title>

Date: YYYY-MM-DD  
From → To: <agent/session> → <agent/next session>  
Scope: <work package id(s) from plan §20, or "narrower child task">

## State of the work

- What is DONE and verified (name the command/test that proves it).
- What is IN PROGRESS and exactly where it stops.
- What is NOT STARTED that a reader might assume was done.

## Decisions made

Decisions taken while working, each either linked to an ADR or explicitly
marked "local, reversible". Never leave a pinned decision implicit in code.

## How to verify

The exact non-interactive commands (build, tests, validator, simulator run)
and their expected results. A handoff without a verification path is not
complete (§18.4).

## Landmines

Non-obvious constraints the next agent could violate: determinism rules,
ID canon, layering bans, provisional values that look final.

## Next steps

Ordered, smallest-first. Note anything blocked and on what.
