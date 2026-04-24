# Sync ThePerch across machines

You have `~/Developer/ThePerch/` on this Mac. When you want to pick
up work on your MacBook (or any other machine), the flow is:

## First-time clone on the other Mac

```bash
mkdir -p ~/Developer
cd ~/Developer
git clone https://github.com/faresende/ThePerch.git
cd ThePerch
```

The clone is small (no build artifacts, no Xcode state). The repo is
gitignore-safe, so none of your secrets ship with it.

### Restore your gitignored secrets

These files live on every machine separately — they're never
committed:

- `ios/ThePerch/Sources/ThePerch/Config/Secrets.xcconfig` — iOS build
  credentials (Supabase URL + publishable key + Karakeep token).

Easiest path: copy `Secrets.xcconfig` from the mini to the MacBook
over iMessage / AirDrop / a password manager one-time. Paste into the
same path on the new machine. That's it.

Template reference is at `Secrets.example.xcconfig` (committed) if
you ever need to rebuild the file from scratch.

## Day-to-day: pick up where you left off

On the machine you're leaving:

```bash
cd ~/Developer/ThePerch
git status                    # make sure nothing uncommitted
git push                      # or git push --force-with-lease if you rebased
```

On the machine you're picking up:

```bash
cd ~/Developer/ThePerch
git pull
open ios/ThePerch/ThePerch.xcodeproj
```

If you ever end up with a reconciliation (force-push on one side,
local commits on the other), favor `git fetch origin main && git
reset --hard origin/main` on the side that's behind — your
uncommitted WIP on that machine gets blown away, but it's usually
safer than trying to merge divergent history.

## What's NOT synced by default

These live outside the repo and are per-machine:

- **Xcode DerivedData** (`~/Library/Developer/Xcode/DerivedData/`) —
  that's fine; it rebuilds on first build.
- **Archives** (`~/Library/Developer/Xcode/Archives/`) — per-machine.
  If you want to upload a TestFlight build you previously archived on
  the other Mac, open Xcode Organizer → Archives → right-click.
- **OpenClaw workspace** (`~/.openclaw/workspace/`) — the agent
  infrastructure lives there and runs on the Mini (which hosts the
  cron daemon). If you want to invoke agents from the MacBook, you'd
  need to install OpenClaw + clone the workspace there too.
- **Supabase `Secrets.xcconfig`** (see above).

## Where the project lived before

Until 2026-04-25, the canonical repo was at
`~/.openclaw/workspace/ThePerch/`. It's now at `~/Developer/ThePerch/`.
The old path is preserved as a backup — safe to delete once you've
confirmed the new location works.

## Tip: avoid iCloud for source code

`~/Developer/` is not iCloud-synced by default on macOS. Keep source
code and repos out of `~/Documents/` (which IS synced if you have
Desktop & Documents enabled in iCloud) — git's thousands of small
`.git/` files thrash the sync engine and can produce weird conflicts
across devices. GitHub is the sync layer for code; iCloud is for
user documents.
