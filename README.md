# tentacle-release-trimmer

Trims old Octopus Deploy release folders from a Windows Tentacle server,
keeping only the N most recent versions per project.

## Quick start

Copy `scripts/Trim-OctopusReleases.ps1` to the Tentacle host and run it in
a PowerShell session (5.1+):

```powershell
.\Trim-OctopusReleases.ps1
```

You will be prompted for run mode:

```
Run mode — [I]nformation only or [D]elete? (default: I)
```

Press **Enter** (or type `I`) to preview what would be removed without making
any changes. Type `D` to delete.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Path` | `C:\Octopus\Applications` | Root of the Octopus applications directory |
| `-KeepVersions` | `2` | Number of most-recent versions to keep per project |

## Folder structure

The script expects:

```
[Path]\[Environment]\[Project]\[Release folders...]
```

Example tree:

```
C:\Octopus\Applications\
  Production\
    MyApp\
      1.0.0\          ← deleted (older than keep window)
      1.0.0_1\        ← deleted (same version as 1.0.0)
      1.1.0\          ← kept
      1.2.0\          ← kept
      1.2.0_1\        ← kept (same version as 1.2.0)
  Staging\
    MyApp\
      ...
```

## Version grouping

Folders with a `_N` suffix (`1.2.3_1`, `1.2.3_2`, …) are counted as the same
version as their base (`1.2.3`). When a version is outside the keep window, all
its folders (base and suffixed) are deleted together.

## Example output

```
Octopus Release Trimmer
  Path          : C:\Octopus\Applications
  Keep versions : 2

Run mode — [I]nformation only or [D]elete? (default: I): I
Mode: INFORMATION — no changes will be made.

  Production / MyApp
    [KEEP]    1.2.0  [1.2.0, 1.2.0_1]  245.3 MB
    [KEEP]    1.1.0  [1.1.0]  230.1 MB
    [TRIM]    C:\Octopus\Applications\Production\MyApp\1.0.0  (228.4 MB)
    [TRIM]    C:\Octopus\Applications\Production\MyApp\1.0.0_1  (12.1 MB)

─────────────────────────────────────────────────────────────────
Would delete: 2 folder(s)  |  Reclaimable: 240.5 MB
```
