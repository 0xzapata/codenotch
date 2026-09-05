# Codenotch

> Working name — not final.

A macOS agent app that pins a small black notch to the **right edge** of the screen
showing how much of each LLM's session limit you have burned, and whether you have hit
the wall yet. Hover a provider to see its individual limit windows and when they reset — and
tells you at a glance whether Claude is still working, done, or waiting on you.
The ring always shows the **current session**, the same window Claude's own usage
panel leads with, so the two never disagree.

![Collapsed notch with hover tooltip](docs/design/frame-124-hover-tooltip.png)

Settings show which account each reading belongs to, with one switch per
provider. Switching on takes you to that account's sign-in — a window for a
provider whose session Codenotch owns, the owning app for Cursor and Codex.
Switching off stops the credential being read and forgets the readings taken from
it, so the numbers do not come back on the next launch. What it cannot do is sign
you out of Claude Code or Cursor: those sessions are theirs, and the row says so
rather than leaving you to find out.
Settings live in an orb below the notch — an arc in the corner at rest, a gear
when you reach for it. It folds away when you are not looking at it: at rest it is a small pill on the
screen edge, and it unfolds when the pointer reaches it. Click to pin it open.

The notch can live on any of the four edges. Right and left keep the vertical
column; top and bottom lay the readings out side by side, because four cells
stacked vertically would hang a quarter of the way down the screen. It pins
itself to the *usable* edge, so a bottom notch rests on top of the Dock — and it
follows when the Dock hides or moves. On a Mac with a notch of its own, the top
placement takes the hardware notch's own shape — straight sides, rounded
underneath, moulded into the frame at the top — so the notch simply looks wider
and deeper rather than having a bar parked underneath it. Folded away it *is*
the notch, and reaching for it makes the notch grow.

Codenotch updates itself. Sparkle checks daily and installs in the background
without prompting, applying the new version the next time the app starts; the
Settings sheet says so and can switch it off. Every update is EdDSA-signed, so
nothing installs that was not built here.

## Status

The notch is built, matches the design frame, and shows **your real Claude
usage** — the same session and weekly percentages Claude's own usage panel
reports, refreshed every 60 seconds. `make run` puts it on screen, hover pops the
detail card.

It also answers **"is Claude still working?"** — inside the Claude ring, a thin
arc spins while a session is working and becomes a pulsing amber ring when one is
blocked waiting on you. Hover for every live session by name, where it is
running, and what it wants.

Two Claude Code logins are two rings. Anyone who keeps a work account apart with
`CLAUDE_CONFIG_DIR=~/.claude-work claude` gets a **Claude (work)** ring beside the
personal one, with its own limits, its own sessions and its own row in Settings.
Any `~/.claude-<slug>` directory Claude Code has run against is found at launch;
the default `~/.claude` always comes first, the rest in alphabetical order, so the
rings never swap places.

Cursor and Codex are wired up too, both reading locally: Cursor borrows the
editor's own session from its SQLite state store, and Codex reads the rate-limit
snapshots it writes into its own rollout logs — no credential, no network.
Perplexity's adapter is kept but unregistered.
Run with `CODENOTCH_DEMO=1` to see the design frame's three-provider layout with
its numbers. See **[TASKS.md](TASKS.md)**.

- Design spec: [`docs/specs/2026-08-28-usage-notch-design.md`](docs/specs/2026-08-28-usage-notch-design.md)
- Implementation plan: [`docs/plans/2026-08-28-usage-notch-plan.md`](docs/plans/2026-08-28-usage-notch-plan.md)
- Design source of truth: [`docs/design/`](docs/design/)

Every size in the UI is measured off the design frame and expressed in frame
pixels (`Design.px(186)`), so the layout is proportionally exact. `Design.scale`
is the one constant that sets the absolute size; it is anchored on the spec's
44pt ring, which puts the notch at 70 x 401pt.

## Stack

Swift 6 / SwiftUI + AppKit, macOS 26, XcodeGen-generated project, agent app
(`LSUIElement`, no Dock icon). Same conventions as `~/notch-app`.

## Build

```sh
brew install xcodegen   # once
make run                # generate, build, launch
make test               # unit tests
```

## The honest caveat

No LLM vendor publishes a clean "your session limit is N% used" API. The data layer is
a set of per-provider adapters that each declare their fidelity — `.official`,
`.derived` or `.manual` — and the UI never presents a derived number as if it were
official.

Claude is `.official`: `ClaudeOAuthProvider` reads the OAuth token Claude Code keeps
in the login keychain and calls `GET /api/oauth/usage`, which is where Claude's own
`/usage` gets its numbers. That is not a published API — it can change without
notice — so the response shape is pinned by tests and every failure degrades to a
visible status (`stale`, `needsAuth`, `error`) rather than to a made-up percentage.

The local session files under `~/.claude/projects` were the original plan. They hold
token counts but no limits and no window metadata, so a percentage from them needs an
invented denominator. They remain the `.derived` fallback if the endpoint disappears.

**Keychain:** the app is signed with a Developer ID identity so the one-time "Always
Allow" grant survives rebuilds. An unsigned build re-prompts after every `make run`.

**Rate limits:** the endpoint returns 429 if polled too hard, and answers
`Retry-After: 0` when it does. The back-off treats that hint as a floor-raiser
only — 60s, doubling per consecutive 429, capped at 15 minutes. The last good
reading is kept across launches, so a refused fetch shows dated numbers rather
than nothing; the ring dims and the tooltip header says how old they are. The
back-off deadline is persisted too, so relaunching during a penalty waits instead
of spending an attempt on it. Polling drops to every 5 minutes when no session is
running, and right-clicking the notch offers **Refresh now**.

**Logs:** the app is an agent with no window, so anything worth diagnosing goes to
the unified log.

```sh
/usr/bin/log stream --predicate 'subsystem == "com.vinz.codenotch"' --level debug
```
