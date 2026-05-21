---
name: winget-tracked-install
description: 'Install WinGet packages locally with before/after system-state tracking, optional neutralization, and optional icon extraction with metadata writing into winget-app-icons/. Use when asked to install a tracked winget package, capture system snapshots around an install, clean up after package installs, extract an app icon after a tracked install, or locally test package installations without polluting the host.'
---

# Install Tracked WinGet Packages Locally

Use this skill to run a local WinGet install while capturing before/after snapshots across processes, services, autorun entries, scheduled tasks, ARP entries, PATH entries, and shortcuts. Installs can then be neutralized to keep the host clean. Optionally extract the icon and populate `winget-app-icons/<PackageId>/` so the output matches CI extraction runs.

Typical inputs: package IDs, pipeline of IDs, or a file list.

## Default Behavior

- Track to `<repo-root>/tracking/<PackageId>/tracking.json`.
- Neutralize after install (stop processes, disable services, remove autorun/scheduled tasks/shortcuts, restore PATH).
- Call through the skill wrapper script from inside the repo.

## Procedure

1. Start from the wrapper script: `scripts/install-tracked-package.ps1`.
2. Use `-PackageId` for one or more package IDs.
3. Use `-ExtractIcon` to also extract the icon and write `metadata.json` + `app-icon.ico` under `winget-app-icons/<PackageId>/`.
4. Use `-NoNeutralize` to keep changes after install.
5. Use `-NoInstall -PackageId <id>` to run snapshot logic against already-installed packages.
6. Use `-Scope` to narrow the install scope (`User`, `Machine`, or `Both`).
7. Inspect the resulting `tracking.json` in the `tracking/` directory and `metadata.json` in `winget-app-icons/`.

## Common Commands

```powershell
# Install a single package and neutralize after
.\.agents\skills\winget-tracked-install\scripts\install-tracked-package.ps1 -PackageId 'Git.Git'

# Install and also extract icon + write metadata into winget-app-icons/
.\.agents\skills\winget-tracked-install\scripts\install-tracked-package.ps1 -PackageId 'Git.Git' -ExtractIcon

# Install multiple packages and keep changes (no neutralization)
.\.agents\skills\winget-tracked-install\scripts\install-tracked-package.ps1 -PackageId 'Git.Git','Microsoft.PowerToys' -NoNeutralize

# Install, extract icon, and keep changes
.\.agents\skills\winget-tracked-install\scripts\install-tracked-package.ps1 -PackageId 'Git.Git' -ExtractIcon -NoNeutralize

# Pipe a list of packages
'Git.Git','Mozilla.Firefox' | .\.agents\skills\winget-tracked-install\scripts\install-tracked-package.ps1

# Dry-run snapshot on already-installed packages
.\.agents\skills\winget-tracked-install\scripts\install-tracked-package.ps1 -PackageId 'Git.Git' -NoInstall

# Only install for the current user
.\.agents\skills\winget-tracked-install\scripts\install-tracked-package.ps1 -PackageId 'Microsoft.VisualStudioCode' -Scope User
```

## Wrapper Script Parameters

- `-PackageId` — One or more WinGet package IDs; accepts pipeline input.
- `-TrackingDir` — Override the default tracking output directory.
- `-Scope` — `User`, `Machine`, or `Both` (default).
- `-Force` — Force reinstall via winget.
- `-TimeoutSeconds` — Max seconds to wait for install (default: 600).
- `-NoNeutralize` — Skip post-install neutralization.
- `-NoInstall` — Skip install; only capture snapshot diffs.
- **`-ExtractIcon`** — After install, extract the icon and write `metadata.json` + `app-icon.ico` under `winget-app-icons/<PackageId>/`.
- **`-PackageStateRoot`** — Root directory for per-package metadata and icon output. Default: `winget-app-icons`.

## Verify And Retry

1. Confirm a `tracking.json` was created under `tracking/<PackageId>/`.
2. If `-ExtractIcon` was used, confirm `winget-app-icons/<PackageId>/metadata.json` exists and `hasIcon` is accurate.
3. Check counts in the tracking JSON to see what the install changed.
4. If neutralization failed, inspect the console output for each dimension.

## Operating Rules

- Do not run tracked installs in the GitHub Actions extraction workflow — this skill is for local testing only.
- Keep the tracking directory under the repo root or a known local path.
- Neutralization is best-effort; review the tracking JSON to verify cleanup.
- When `-ExtractIcon` is used, the metadata schema matches the CI bulk extraction so downstream catalog queries work seamlessly.

## References

- [Wrapper script](./scripts/install-tracked-package.ps1)
- [Tracking report fields](./references/tracking-fields.md)
