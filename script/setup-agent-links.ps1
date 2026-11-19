#!/usr/bin/env pwsh
#
# Link the agent resources in .agent/ into the vendor-specific locations that
# Claude Code, Codex and opencode read.
#
# .agent/ is the source of truth. The vendor directories only ever receive
# directory junctions (or, for single files, a symbolic or hard link); this
# script never copies, moves or deletes real data.
#
# Run in a console, the script first shows a checklist of the agents to set
# up, and any number of them can be selected. Without a console, or with
# -Agents / -All, the checklist is skipped.
#
# Usage: .\script\setup-agent-links.ps1 [-Agents <list> | -All]
#        (runnable from any working directory; see -Help)

[CmdletBinding()]
param(
    # Agents to set up, skipping the checklist: claude, codex, opencode.
    [string[]]$Agents,
    # Set up every agent, skipping the checklist.
    [switch]$All,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Agents
#
# The checklist lists the agents in this order. Ids are what -Agents accepts
# and what the Agents field of the mappings below refers to.
# ---------------------------------------------------------------------------

$AgentCatalog = @(
    @{ Id = 'claude';   Label = 'Claude Code'; Hint = '.claude/, .mcp.json, CLAUDE.md'                    }
    @{ Id = 'codex';    Label = 'Codex';       Hint = '.agents/skills, .codex/rules'                      }
    @{ Id = 'opencode'; Label = 'OpenCode';    Hint = '.agents/skills, .opencode/commands, opencode.json' }
)

# ---------------------------------------------------------------------------
# Resource mapping
#
# To support a new resource, add one entry. A link is created when at least
# one of its Agents is selected. Paths are relative to the project root, and
# the mapping is kept identical to the Bash script's.
# ---------------------------------------------------------------------------

$DirectoryLinks = @(
    @{ Name = 'skills';   Agents = @('claude');            Source = '.agent/skills';   Target = '.claude/skills'     }
    @{ Name = 'skills';   Agents = @('codex', 'opencode'); Source = '.agent/skills';   Target = '.agents/skills'     }
    @{ Name = 'rules';    Agents = @('claude');            Source = '.agent/rules';    Target = '.claude/rules'      }
    @{ Name = 'agents';   Agents = @('claude');            Source = '.agent/agents';   Target = '.claude/agents'     }
    @{ Name = 'commands'; Agents = @('claude');            Source = '.agent/commands'; Target = '.claude/commands'   }
    @{ Name = 'commands'; Agents = @('opencode');          Source = '.agent/commands'; Target = '.opencode/commands' }
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
#   guardrails Permission deny rules rendered by script/generate-guardrails.sh
#              from .agent/guardrails/protected-branches, one file per agent.
$FileLinks = @(
    @{ Name = 'mcp';          Agents = @('claude');   Source = '.agent/mcp.json';                        Target = '.mcp.json'                     }
    @{ Name = 'instructions'; Agents = @('claude');   Source = 'AGENTS.md';                              Target = 'CLAUDE.md'                     }
    @{ Name = 'guardrails';   Agents = @('claude');   Source = '.agent/guardrails/claude-settings.json'; Target = '.claude/settings.json'         }
    @{ Name = 'guardrails';   Agents = @('opencode'); Source = '.agent/guardrails/opencode.json';        Target = 'opencode.json'                 }
    @{ Name = 'guardrails';   Agents = @('codex');    Source = '.agent/guardrails/codex.rules';          Target = '.codex/rules/guardrails.rules' }
)

$Usage = @'
Usage: .\script\setup-agent-links.ps1 [-Agents <list> | -All]

Link the agent resources in .agent/ into the paths each coding agent reads.

Without a parameter, a checklist of agents opens in the console. Select any
number of them:
  Up/Down, k/j  move          Space  toggle        a  select all / none
  Enter         confirm       q, Esc cancel
Without a usable console the checklist is skipped and every agent is set up:
CI, redirected input or output, -NonInteractive, most coding agents' shells,
and on Linux/macOS a TERM that is unset or dumb.
Automation that does run in a console should pass -All or -Agents.

Parameters:
  -Agents <list>  Set up only these agents, skipping the checklist.
                  Comma-separated: claude, codex, opencode
  -All            Set up every agent, skipping the checklist
  -Help           Show this help

Example:
  .\script\setup-agent-links.ps1 -Agents claude,codex
'@

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
# Agent selection
# ---------------------------------------------------------------------------

# Agent ids in checklist order.
$script:SelectedAgents = @()

function Exit-UsageError {
    param([string]$Detail)
    Write-Host "[ERROR] $Detail" -ForegroundColor Red
    Write-Host '        Run with -Help for usage.' -ForegroundColor Red
    exit 2
}

# Agent id for a name given on the command line, or $null when unknown.
function Get-AgentId {
    param([string]$Name)
    $key = $Name.Trim().ToLowerInvariant()
    if ($key -in @('claude', 'claude-code', 'claudecode')) { return 'claude' }
    if ($key -eq 'codex') { return 'codex' }
    if ($key -in @('opencode', 'open-code')) { return 'opencode' }
    return $null
}

# Sets the selection from -Agents. Each item may itself be a comma-separated
# list, because `pwsh -File` passes `-Agents claude,codex` as a single string.
function Select-AgentsFromList {
    param([string[]]$Names)
    $wanted = @{}
    foreach ($item in @($Names)) {
        foreach ($part in ([string]$item -split ',')) {
            $name = $part.Trim()
            if (-not $name) { continue }
            $id = Get-AgentId $name
            if (-not $id) {
                Exit-UsageError "unknown agent '$name' in -Agents; expected claude, codex or opencode"
            }
            $wanted[$id] = $true
        }
    }
    if ($wanted.Count -eq 0) {
        Exit-UsageError '-Agents needs at least one of claude, codex, opencode'
    }
    $script:SelectedAgents = @($AgentCatalog | Where-Object { $wanted.ContainsKey($_.Id) } | ForEach-Object { $_.Id })
}

function Select-AllAgents {
    $script:SelectedAgents = @($AgentCatalog | ForEach-Object { $_.Id })
}

# True when at least one of the given agent ids is selected.
function Test-AnyAgentSelected {
    param([string[]]$Ids)
    foreach ($id in $Ids) {
        if ($script:SelectedAgents -contains $id) { return $true }
    }
    return $false
}

function Get-SelectedAgentLabels {
    $labels = @($AgentCatalog | Where-Object { $script:SelectedAgents -contains $_.Id } | ForEach-Object { $_.Label })
    return ($labels -join ', ')
}

# ---------------------------------------------------------------------------
# Checklist (TUI)
#
# Every line is padded to the width of the longest line, so each redraw
# overwrites the previous one in place, and cut to the console width, so the
# drawing never wraps. Padding only to the content width, not to the window
# width, keeps the lines from re-wrapping when the window is narrowed.
#
# The checklist is written to the console with [Console], not Write-Host.
# Write-Host goes to the information stream, which `*>` or `6>` would send to
# a file while ReadKey still waits for a key on the console.
# ---------------------------------------------------------------------------

function Test-ChecklistAvailable {
    try {
        if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return $false }
    }
    catch {
        return $false
    }
    if (-not [Environment]::UserInteractive) { return $false }
    # As in the Bash script: a Unix terminal without TERM, or a dumb one, cannot
    # move the cursor, so every redraw would be appended below the last one.
    # ($IsWindows is not used: it does not exist in Windows PowerShell 5.1.)
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Unix) {
        if (-not $env:TERM -or $env:TERM -eq 'dumb') { return $false }
    }
    # -NonInteractive, an abbreviation of it, or pwsh's --noninteractive.
    foreach ($arg in [Environment]::GetCommandLineArgs()) {
        if ($arg -match '^(--?|/)non($|i)') { return $false }
    }
    return $true
}

# Width to draw the checklist at: the longest line, or one column short of
# the console edge if that is narrower, since some consoles wrap when the last
# column is written.
function Get-ChecklistWidth {
    param([int]$ContentWidth)
    $width = 0
    try { $width = [Console]::WindowWidth } catch { }
    if ($width -le 0) { $width = 80 }
    if ($width -gt 1) { $width-- }
    return [Math]::Min($ContentWidth, $width)
}

function Write-ChecklistLine {
    param([string]$Text, [int]$Width, [switch]$Highlight)
    if ($Text.Length -gt $Width) { $Text = $Text.Substring(0, $Width) }
    $Text = $Text.PadRight($Width)
    if ($Highlight) {
        # Put back the color that was set rather than calling ResetColor,
        # which would also discard colors the user set for the session.
        $previous = [Console]::ForegroundColor
        [Console]::ForegroundColor = [ConsoleColor]::Cyan
        [Console]::Write($Text)
        [Console]::ForegroundColor = $previous
        [Console]::WriteLine()
    }
    else {
        [Console]::WriteLine($Text)
    }
}

# Moves the cursor to the first line of the checklist drawn just above it. The
# position is measured from the cursor every time instead of being cached, so
# a console resized while the checklist waits for a key is followed. If the
# cursor cannot be moved, the next drawing simply starts below the last one.
function Move-ToChecklistTop {
    param([int]$LineCount)
    try {
        [Console]::SetCursorPosition(0, [Math]::Max(0, [Console]::CursorTop - $LineCount))
    }
    catch { }
}

# Runs the checklist and sets the selection. Returns $false, with nothing
# selected, when this console cannot read single key presses. Exits on cancel.
function Select-AgentsWithChecklist {
    $count = $AgentCatalog.Count
    $checked = New-Object 'bool[]' $count
    for ($i = 0; $i -lt $count; $i++) { $checked[$i] = $true }
    $cursor = 0
    $message = ''
    $lineCount = $count + 5
    $title = 'Select the agents to set up (any number):'
    $keyHelp = '  Up/Down move  Space toggle  a all/none  Enter confirm  q cancel'
    $emptyMessage = 'Select at least one agent with Space, or press q to cancel.'
    $rows = @(for ($i = 0; $i -lt $count; $i++) {
            '{0} {1}' -f $AgentCatalog[$i].Label.PadRight(13), $AgentCatalog[$i].Hint
        })
    $contentWidth = (@($title, $keyHelp, "  $emptyMessage") + @($rows | ForEach-Object { "  > [x] $_" }) |
        Measure-Object -Property Length -Maximum).Maximum
    $drawn = $false
    $outcome = 'selected'
    $selected = @()

    # Ctrl-C is read as a key so the console is always restored before exit.
    $savedTreatControlC = $null
    try {
        $savedTreatControlC = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true
    }
    catch { }
    try { [Console]::CursorVisible = $false } catch { }

    try {
        while ($true) {
            $width = Get-ChecklistWidth $contentWidth
            if ($drawn) { Move-ToChecklistTop $lineCount }

            Write-ChecklistLine $title $width
            Write-ChecklistLine $keyHelp $width
            Write-ChecklistLine '' $width
            for ($i = 0; $i -lt $count; $i++) {
                $mark = if ($checked[$i]) { 'x' } else { ' ' }
                $pointer = if ($i -eq $cursor) { '>' } else { ' ' }
                Write-ChecklistLine ('  {0} [{1}] {2}' -f $pointer, $mark, $rows[$i]) $width -Highlight:($i -eq $cursor)
            }
            Write-ChecklistLine '' $width
            Write-ChecklistLine "  $message" $width
            $drawn = $true

            try {
                $key = [Console]::ReadKey($true)
            }
            catch [System.InvalidOperationException] {
                $outcome = 'unsupported'
                break
            }

            $message = ''
            $char = [string]$key.KeyChar
            $isControlC = ($key.KeyChar -eq [char]3) -or
                (($key.Key -eq [ConsoleKey]::C) -and ($key.Modifiers -band [ConsoleModifiers]::Control))

            if ($isControlC) {
                $outcome = 'interrupted'
                break
            }
            elseif ($key.Key -eq [ConsoleKey]::UpArrow -or $char -eq 'k') {
                $cursor = ($cursor + $count - 1) % $count
            }
            elseif ($key.Key -eq [ConsoleKey]::DownArrow -or $char -eq 'j') {
                $cursor = ($cursor + 1) % $count
            }
            elseif ($key.Key -eq [ConsoleKey]::Spacebar) {
                $checked[$cursor] = -not $checked[$cursor]
            }
            elseif ($char -eq 'a') {
                $allChecked = -not ($checked -contains $false)
                for ($i = 0; $i -lt $count; $i++) { $checked[$i] = -not $allChecked }
            }
            elseif ($key.Key -eq [ConsoleKey]::Enter) {
                $selected = @(for ($i = 0; $i -lt $count; $i++) { if ($checked[$i]) { $AgentCatalog[$i].Id } })
                if ($selected.Count -gt 0) { break }
                $message = $emptyMessage
            }
            elseif ($key.Key -eq [ConsoleKey]::Escape -or $char -eq 'q') {
                $outcome = 'cancelled'
                break
            }
        }
    }
    finally {
        # Erase the checklist and leave the cursor where its first line was.
        if ($drawn) {
            try {
                $width = Get-ChecklistWidth $contentWidth
                Move-ToChecklistTop $lineCount
                $top = [Console]::CursorTop
                for ($i = 0; $i -lt $lineCount; $i++) { [Console]::WriteLine(' ' * $width) }
                [Console]::SetCursorPosition(0, $top)
            }
            catch { }
        }
        try { [Console]::CursorVisible = $true } catch { }
        if ($null -ne $savedTreatControlC) {
            try { [Console]::TreatControlCAsInput = $savedTreatControlC } catch { }
        }
    }

    switch ($outcome) {
        'unsupported' { return $false }
        'interrupted' { Write-Host 'Cancelled. Nothing was changed.'; exit 130 }
        'cancelled' { Write-Host 'Cancelled. Nothing was changed.'; exit 1 }
    }
    $script:SelectedAgents = $selected
    return $true
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if ($Help) {
    Write-Host $Usage
    exit 0
}

if ($PSBoundParameters.ContainsKey('Agents') -and $All) {
    Exit-UsageError '-Agents and -All cannot be used together'
}

if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.agent') -PathType Container)) {
    Write-Host "[ERROR] .agent does not exist at $projectRoot" -ForegroundColor Red
    Write-Host '        .agent is the source of truth for agent resources and must be present.' -ForegroundColor Red
    exit 1
}

$selectionNote = $null
if ($PSBoundParameters.ContainsKey('Agents')) {
    Select-AgentsFromList $Agents
}
elseif ($All) {
    Select-AllAgents
}
elseif (-not ((Test-ChecklistAvailable) -and (Select-AgentsWithChecklist))) {
    Select-AllAgents
    $selectionNote = 'no usable console for the checklist, so every agent is set up; choose with -Agents'
}

Write-Host 'Agent resource setup'
Write-Host ("  project root: {0}" -f $projectRoot)
Write-Host ("  agents:       {0}" -f (Get-SelectedAgentLabels))
if ($selectionNote) {
    Write-Host ("                ({0})" -f $selectionNote)
}
Write-Host ''

# Created when absent; any existing contents are left untouched.
if (Test-AnyAgentSelected @('claude')) {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.claude') -Force | Out-Null
}

foreach ($link in $DirectoryLinks) {
    if (-not (Test-AnyAgentSelected $link.Agents)) { continue }
    Set-DirectoryLink -Name $link.Name -SourceRelative $link.Source -TargetRelative $link.Target
}

foreach ($link in $FileLinks) {
    if (-not (Test-AnyAgentSelected $link.Agents)) { continue }
    Set-FileLink -Name $link.Name -SourceRelative $link.Source -TargetRelative $link.Target
}

Write-Host ''
if ($script:Failures -gt 0) {
    Write-Host ("Failed: {0} resource(s) could not be linked. See [ERROR] above." -f $script:Failures) -ForegroundColor Red
    exit 1
}
Write-Host 'Done.'
