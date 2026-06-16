# SweepDock

SweepDock is a small native macOS desktop wrapper for the free Mole CLI.

## Attribution

This is an unofficial wrapper for [Mole](https://github.com/tw93/Mole) by tw93.
It is not affiliated with, endorsed by, or sponsored by the Mole project.

SweepDock does not include Mole source code. It detects and invokes the locally
installed `mo` executable.

Mole's official names, logos, and commercial macOS app branding belong to their
respective owners. This project uses its own name and generated icon.

It does not reimplement Mole cleanup logic. It detects the local `mo` executable and runs commands through a safer desktop flow:

- `mo status`
- `mo analyze --json`
- `mo clean --dry-run`
- `mo clean` after a confirmation dialog
- `mo history --json`
- `mo uninstall --list`
- `mo uninstall --dry-run <app>`
- `mo uninstall <app>` after a same-app preview and confirmation
- `mo purge --dry-run`
- `mo optimize --dry-run`
- `mo optimize` after a preview and confirmation
- `mo --help`

`mo analyze` without `--json` is a terminal TUI and requires a real TTY. SweepDock intentionally uses `mo analyze --json` so disk analysis works inside a desktop app.

## Build

The current implementation lives in `native/main.m` and is packaged by
`build_app.sh`. Older Swift/Python prototype files are kept for reference only.

```bash
cd SweepDock
./build_app.sh
```

## Run

```bash
open SweepDock.app
```

## Self Test

The built app includes a non-GUI self test that exercises the same command runner used by the UI:

```bash
SweepDock.app/Contents/MacOS/SweepDock --self-test
```

It verifies:

- `mo --help`
- `mo status`
- `mo analyze --json`
- `mo clean --dry-run`
- `mo history --json`
- `mo uninstall --list`
- `mo purge --dry-run`
- `mo optimize --dry-run`
- JSON formatting for disk analysis
- formatted status, cleanup preview, history, uninstall list, project purge, and optimize output

## Requirements

- macOS 12 or newer
- Xcode Command Line Tools for building
- Mole CLI installed separately: `brew install mole`

## License

GPL-3.0. See `LICENSE`.

## Safety

The UI makes dry-run cleanup the main path. Real cleanup requires a successful cleanup preview first, then a second confirmation, because Mole can permanently delete cache, log, and generated files.

App uninstall also requires a successful same-app preview before the real uninstall button is allowed. SweepDock does not expose Mole's `--permanent` uninstall option; by default Mole moves removed files to the macOS Trash.

## Current Features

- Chinese native AppKit UI
- Structured system status summary
- Disk analysis through `mo analyze --json`, with a table view
- Double-click disk analysis folders to drill into a local directory view
- Open selected analysis items in Finder or move selected items to the macOS Trash
- Structured cleanup preview with table rows and detailed file list shortcuts
- Real cleanup guarded by a required successful preview and a confirmation dialog
- Cleanup history through `mo history --json`
- App uninstall list with table selection, app-specific uninstall preview, and guarded real uninstall
- Shared table search/filter for disk analysis, cleanup preview, and app uninstall lists
- Status/tag quick filter for table rows, useful for cleanup preview states such as cleanable, skipped, normal, and review-needed
- Result summary line for status, disk analysis, cleanup preview, cleanup category stats, history, uninstall list, project purge, and optimize preview
- Project artifact purge preview
- System optimize preview and guarded real optimize
- Copy current output, open generated clean list, copy list path, and open Mole operation logs
