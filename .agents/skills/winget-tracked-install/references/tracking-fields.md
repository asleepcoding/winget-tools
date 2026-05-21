# Tracking Report Fields

Each `tracking.json` written by `Install-TrackedWingetPackage` follows this schema:

| Field | Type | Description |
|-------|------|-------------|
| `packageId` | string | WinGet package ID |
| `timestamp` | ISO-8601 string | When the report was written |
| `installResult` | string | `success`, `already-installed`, `failed`, `no-install`, or `whatif` |
| `installExitCode` | int or null | Exit code from winget, if applicable |
| `installDurationSec` | float | Time spent in install/snapshot steps |
| `installOutput` | string or null | stdout from winget install |
| `installError` | string or null | stderr from winget install |
| `counts` | object | Summary counts for each tracked dimension |
| `diffs` | object | Full per-dimension before/after diffs |

## Counts

- `Processes` — Number of new processes after install.
- `Services` — Number of new services.
- `Autorun` — Number of new autorun entries.
- `ScheduledTasks` — Number of new scheduled tasks.
- `Arp` — Number of new ARP entries.
- `PathMachine` / `PathUser` — Number of new PATH additions per scope.
- `Shortcuts` — Number of new shortcuts.

## Diffs

Each key under `diffs` holds the full list of detected additions. `Path` splits into `Machine` and `User` arrays.

## Combined with Icon Extraction

When the `-ExtractIcon` parameter is used, the wrapper also writes a `metadata.json`
under `winget-app-icons/<PackageId>/` matching the CI extraction schema.
That file contains the standard catalog fields (`status`, `hasIcon`, `iconBytes`,
etc.) plus a nested `tracking` object with `trackingPath` and `counts` from the
report above.
