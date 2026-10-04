#!/usr/bin/env pwsh
#
# Link the agent resources in .agent/ into the vendor-specific locations that
# Claude Code, Codex and opencode read.
#
# .agent/ is the source of truth. The vendor directories only ever receive
# directory junctions (or, for single files, a symbolic or hard link); this
# script never copies, moves or deletes real data.
#
# Usage: .\script\setup-agent-links.ps1   (runnable from any working directory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Resource mapping
#
# To support a new resource, add one entry. Paths are relative to the project
# root and kept identical to the Bash script's mapping.
# ---------------------------------------------------------------------------

$DirectoryLinks = @(
    @{ Name = 'skills';   Source = '.agent/skills';   Target = '.claude/skills'     }
    @{ Name = 'skills';   Source = '.agent/skills';   Target = '.agents/skills'     }
    @{ Name = 'rules';    Source = '.agent/rules';    Target = '.claude/rules'      }
    @{ Name = 'agents';   Source = '.agent/agents';   Target = '.claude/agents'     }
    @{ Name = 'commands'; Source = '.agent/commands'; Target = '.claude/commands'   }
    @{ Name = 'commands'; Source = '.agent/commands'; Target = '.opencode/commands' }
)

# Single files cannot be directory junctions, because a junction only ever
# points at a directory, so they are tracked separately. Both sources stay
# vendor-neutral:
#
#   .mcp.json  Claude Code reads project-scoped MCP servers from this one file
#              at the project root, in {"mcpServers": {...}} form. There is no
#              .claude/mcp directory, so the source is the single file
#              .agent/mcp.json rather than a directory.
#   CLAUDE.md  Claude Code v2.1.277+ reads AGENTS.md directly, but older
#              versions need a CLAUDE.md. Linking the two keeps one source.
$FileLinks = @(
    @{ Name = 'mcp';          Source = '.agent/mcp.json'; Target = '.mcp.json' }
    @{ Name = 'instructions'; Source = 'AGENTS.md';       Target = 'CLAUDE.md' }
)

# ---------------------------------------------------------------------------
# Project root, derived from this file's own location
# ---------------------------------------------------------------------------

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

$script:Failures = 0

function Write-Status {
    param([string]$Status, [string]$Name, [string]$Detail)
    $label = "[$Status]".PadRight(8)
    Write-Host ("{0}{1} {2}" -f $label, $Name.PadRight(12), $Detail)
}

function Write-Failure {
    param([string]$Name, [string]$Detail)
    $label = '[ERROR]'.PadRight(8)
    Write-Host ("{0}{1} {2}" -f $label, $Name.PadRight(12), $Detail) -ForegroundColor Red
    $script:Failures++
}

function Join-ProjectPath {
    param([string]$Relative)
    $native = $Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    return [System.IO.Path]::GetFullPath((Join-Path $projectRoot $native))
}

function Test-SamePath {
    param([string]$A, [string]$B)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $trim = [char[]]@($sep, '/')
    $normA = $A.TrimEnd($trim)
    $normB = $B.TrimEnd($trim)
    return [string]::Equals($normA, $normB, [System.StringComparison]::OrdinalIgnoreCase)
}

# Resolved absolute path a junction or symbolic link points at, or $null.
function Get-LinkTarget {
    param([System.IO.FileSystemInfo]$Item)
    $raw = @($Item.Target) | Where-Object { $_ } | Select-Object -First 1
    if (-not $raw) { return $null }
    if ([System.IO.Path]::IsPathRooted($raw)) {
        return [System.IO.Path]::GetFullPath($raw)
    }
    # Relative links resolve against the directory holding the link.
    return [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $Item.FullName) $raw))
}

# Detaches a junction, symbolic link or hard link without touching the data
# behind it. Remove-Item -Recurse is deliberately never used here: on a
# junction it can delete the contents of the link's target.
function Remove-LinkOnly {
    param([System.IO.FileSystemInfo]$Item)
    if ($Item.PSIsContainer) {
        [System.IO.Directory]::Delete($Item.FullName)
    }
    else {
        [System.IO.File]::Delete($Item.FullName)
    }
}

function Get-ExistingItem {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Item -LiteralPath $Path -Force
}

function Set-DirectoryLink {
    param([string]$Name, [string]$SourceRelative, [string]$TargetRelative)

    $source = Join-ProjectPath $SourceRelative
    $target = Join-ProjectPath $TargetRelative

    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        Write-Status 'SKIP' $Name "$SourceRelative does not exist"
        return
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null

    $action = 'OK'
    $item = Get-ExistingItem $target
    if ($item) {
        if ($item.LinkType -in @('Junction', 'SymbolicLink')) {
            $current = Get-LinkTarget $item
            if ($current -and (Test-SamePath $current $source)) {
                Write-Status 'OK' $Name "$TargetRelative already points to $SourceRelative"
                return
            }
            Remove-LinkOnly $item
            $action = 'RELINK'
        }
        else {
            Write-Failure $Name "$TargetRelative already exists and is not a link; refusing to overwrite existing data"
            return
        }
    }

    # Junctions need no elevation and no Developer Mode, unlike directory
    # symbolic links, so they are the default for directories.
    New-Item -ItemType Junction -Path $target -Value $source | Out-Null
    Write-Status $action $Name "$TargetRelative -> $SourceRelative"
}

function Set-FileLink {
    param([string]$Name, [string]$SourceRelative, [string]$TargetRelative)

    $source = Join-ProjectPath $SourceRelative
    $target = Join-ProjectPath $TargetRelative

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Write-Status 'SKIP' $Name "$SourceRelative does not exist"
        return
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null

    $action = 'OK'
    $item = Get-ExistingItem $target
    if ($item) {
        $linkType = [string]$item.LinkType
        if ($linkType -eq 'SymbolicLink') {
            $current = Get-LinkTarget $item
            if ($current -and (Test-SamePath $current $source)) {
                Write-Status 'OK' $Name "$TargetRelative already points to $SourceRelative"
                return
            }
            Remove-LinkOnly $item
            $action = 'RELINK'
        }
        elseif ($linkType -eq 'HardLink') {
            # A hard link exposes no target path, so identity is checked by
            # content. An editor that saves by replacing the file (write to a
            # temp file, then rename) breaks the link, and the two sides drift
            # apart. Re-linking would discard whichever copy is newer, so this
            # is reported rather than repaired.
            $same = (Get-FileHash -LiteralPath $target).Hash -eq (Get-FileHash -LiteralPath $source).Hash
            if ($same) {
                Write-Status 'OK' $Name "$TargetRelative is hard-linked to $SourceRelative"
                return
            }
            Write-Failure $Name "$TargetRelative is a hard link whose contents no longer match $SourceRelative; compare both files, delete $TargetRelative, then re-run"
            return
        }
        else {
            Write-Failure $Name "$TargetRelative already exists and is not a link; refusing to overwrite existing data"
            return
        }
    }

    # A file symbolic link is the faithful equivalent of the POSIX link, but
    # creating one needs Developer Mode or an elevated shell. A hard link needs
    # neither, so it is the fallback. Both keep a single copy of the file on
    # disk; the file is never duplicated.
    try {
        New-Item -ItemType SymbolicLink -Path $target -Value $source -ErrorAction Stop | Out-Null
        Write-Status $action $Name "$TargetRelative -> $SourceRelative (symbolic link)"
        return
    }
    catch {
        $symlinkError = $_.Exception.Message
    }

    try {
        New-Item -ItemType HardLink -Path $target -Value $source -ErrorAction Stop | Out-Null
        Write-Status $action $Name "$TargetRelative -> $SourceRelative (hard link)"
        return
    }
    catch {
        Write-Failure $Name @"
$TargetRelative could not be linked to $SourceRelative.
         A file symbolic link failed: $symlinkError
         A hard link failed: $($_.Exception.Message)
         $TargetRelative is a single file, not a directory, so this mapping cannot use a
         directory junction. Enable Windows Developer Mode (Settings >
         System > For developers) to allow unprivileged symbolic links, or keep $SourceRelative
         and $TargetRelative on the same NTFS volume so a hard link can be created. This script
         does not copy the file, because a copy would silently stop tracking $SourceRelative.
"@
    }
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

Write-Host 'Agent resource setup'
Write-Host ("  project root: {0}" -f $projectRoot)
Write-Host ''

if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.agent') -PathType Container)) {
    Write-Host "[ERROR] .agent does not exist at $projectRoot" -ForegroundColor Red
    Write-Host '        .agent is the source of truth for agent resources and must be present.' -ForegroundColor Red
    exit 1
}

# Created when absent; any existing contents are left untouched.
New-Item -ItemType Directory -Path (Join-Path $projectRoot '.claude') -Force | Out-Null

foreach ($link in $DirectoryLinks) {
    Set-DirectoryLink -Name $link.Name -SourceRelative $link.Source -TargetRelative $link.Target
}

foreach ($link in $FileLinks) {
    Set-FileLink -Name $link.Name -SourceRelative $link.Source -TargetRelative $link.Target
}

Write-Host ''
if ($script:Failures -gt 0) {
    Write-Host ("Failed: {0} resource(s) could not be linked. See [ERROR] above." -f $script:Failures) -ForegroundColor Red
    exit 1
}
Write-Host 'Done.'
