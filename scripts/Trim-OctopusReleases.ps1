#Requires -Version 5.1
<#
.SYNOPSIS
    Trims old Octopus Deploy release folders, keeping only the N most recent
    versions per project.

.DESCRIPTION
    Walks [Path]\[Environment]\[Project]\[Release] trees, groups release
    folders by their base SemVer (folders suffixed _1, _2, etc. count as the
    same version), and either reports or removes all but the N most recent.

.PARAMETER Path
    Root of the Octopus applications folder. Defaults to C:\Octopus\Applications.

.PARAMETER KeepVersions
    Number of most-recent versions to retain per project. Defaults to 2.

.EXAMPLE
    .\Trim-OctopusReleases.ps1
    Interactive run with defaults (C:\Octopus\Applications, keep 2).

.EXAMPLE
    .\Trim-OctopusReleases.ps1 -Path D:\Apps -KeepVersions 3
    Custom path, keep 3 versions.
#>

[CmdletBinding()]
param(
    [string]$Path = "C:\Octopus\Applications",

    [ValidateRange(1, 100)]
    [int]$KeepVersions = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── helpers ─────────────────────────────────────────────────────────────────

function Get-BaseVersion([string]$FolderName) {
    # "1.2.3_1" -> "1.2.3"
    return $FolderName -replace '_\d+$', ''
}

function ConvertTo-SortableVersion([string]$VersionString) {
    $v = $null
    if ([System.Version]::TryParse($VersionString, [ref]$v)) { return $v }
    # Non-parseable names sort to the bottom (preserved, not deleted)
    return [System.Version]'0.0.0.0'
}

function Get-FolderSizeMB([string]$FolderPath) {
    $bytes = 0L
    Get-ChildItem -Path $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { $bytes += $_.Length }
    return [math]::Round($bytes / 1MB, 1)
}

function Write-Section([string]$Text) {
    Write-Host "`n  $Text" -ForegroundColor Cyan
}

function Write-Keep([string]$Text) {
    Write-Host "    [KEEP]    $Text" -ForegroundColor Green
}

function Write-Trim([string]$Text) {
    Write-Host "    [TRIM]    $Text" -ForegroundColor Yellow
}

function Write-Deleted([string]$Text) {
    Write-Host "    [DELETED] $Text" -ForegroundColor Red
}

function Write-Err([string]$Text) {
    Write-Host "    [ERROR]   $Text" -ForegroundColor Magenta
}

# ── validation ───────────────────────────────────────────────────────────────

if (-not (Test-Path -Path $Path -PathType Container)) {
    Write-Error "Applications path not found: $Path"
    exit 1
}

# ── mode selection ───────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Octopus Release Trimmer" -ForegroundColor White
Write-Host "  Path          : $Path" -ForegroundColor DarkGray
Write-Host "  Keep versions : $KeepVersions" -ForegroundColor DarkGray
Write-Host ""

$modeInput = Read-Host "Run mode — [I]nformation only or [D]elete? (default: I)"

if ([string]::IsNullOrWhiteSpace($modeInput)) { $modeInput = 'I' }
$modeInput = $modeInput.Trim().ToUpper()

if ($modeInput -notin @('I', 'D')) {
    Write-Error "Invalid choice '$modeInput'. Enter I or D."
    exit 1
}

$deleteMode = $modeInput -eq 'D'

Write-Host ""
if ($deleteMode) {
    Write-Host "Mode: DELETE — folders will be permanently removed." -ForegroundColor Red
} else {
    Write-Host "Mode: INFORMATION — no changes will be made." -ForegroundColor Cyan
}

# ── traversal ────────────────────────────────────────────────────────────────

$totalFolders    = 0
$totalDeleted    = 0
$totalErrors     = 0
$totalSizeMB     = 0.0

$environments = Get-ChildItem -Path $Path -Directory -ErrorAction Stop

foreach ($envDir in $environments) {

    $projects = Get-ChildItem -Path $envDir.FullName -Directory -ErrorAction Continue

    foreach ($projectDir in $projects) {

        $releaseDirs = Get-ChildItem -Path $projectDir.FullName -Directory -ErrorAction Continue
        if (-not $releaseDirs) { continue }

        # Group release folders by base version
        $groups = [ordered]@{}
        foreach ($dir in $releaseDirs) {
            $base = Get-BaseVersion $dir.Name
            if (-not $groups.Contains($base)) {
                $groups[$base] = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
            }
            $groups[$base].Add($dir)
        }

        # Sort base versions descending by SemVer
        $sortedBases = $groups.Keys |
            Sort-Object -Property { ConvertTo-SortableVersion $_ } -Descending

        $keepBases   = @($sortedBases | Select-Object -First $KeepVersions)
        $deleteBases = @($sortedBases | Select-Object -Skip  $KeepVersions)

        if ($deleteBases.Count -eq 0) { continue }

        Write-Section "$($envDir.Name) / $($projectDir.Name)"

        foreach ($base in $keepBases) {
            $folders = @($groups[$base] | Sort-Object Name)
            $sizeMB  = 0.0
            $folders | ForEach-Object { $sizeMB += Get-FolderSizeMB $_.FullName }
            $names   = ($folders | Select-Object -ExpandProperty Name) -join ', '
            Write-Keep "$base  [$names]  $([math]::Round($sizeMB, 1)) MB"
        }

        foreach ($base in $deleteBases) {
            $folders = $groups[$base] | Sort-Object Name
            foreach ($dir in $folders) {
                $sizeMB       = Get-FolderSizeMB $dir.FullName
                $totalSizeMB += $sizeMB
                $totalFolders++

                if ($deleteMode) {
                    try {
                        Remove-Item -Path $dir.FullName -Recurse -Force
                        Write-Deleted "$($dir.FullName)  ($sizeMB MB)"
                        $totalDeleted++
                    } catch {
                        Write-Err "$($dir.FullName) — $($_.Exception.Message)"
                        $totalErrors++
                    }
                } else {
                    Write-Trim "$($dir.FullName)  ($sizeMB MB)"
                }
            }
        }
    }
}

# ── summary ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host ("─" * 65) -ForegroundColor DarkGray

if ($deleteMode) {
    $colour = if ($totalErrors -gt 0) { 'Yellow' } else { 'Green' }
    Write-Host (
        "Deleted: $totalDeleted folder(s)  |  Errors: $totalErrors  |  " +
        "Reclaimed: $([math]::Round($totalSizeMB, 1)) MB"
    ) -ForegroundColor $colour
    if ($totalErrors -gt 0) {
        Write-Host "Some folders could not be removed (see [ERROR] lines above)." -ForegroundColor Magenta
    }
} else {
    Write-Host (
        "Would delete: $totalFolders folder(s)  |  " +
        "Reclaimable: $([math]::Round($totalSizeMB, 1)) MB"
    ) -ForegroundColor Yellow
    if ($totalFolders -eq 0) {
        Write-Host "Nothing to trim — all projects are within the $KeepVersions-version limit." -ForegroundColor Green
    }
}

Write-Host ""
