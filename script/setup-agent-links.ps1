<#
.SYNOPSIS
    .agent (정본) -> 각 도구가 요구하는 고정 경로로 링크를 건다. (Windows / PowerShell)

.DESCRIPTION
    Windows 에서는 디렉터리에 junction 을 우선 사용한다(관리자 권한·개발자 모드가 필요 없다).
    junction 이 실패하면 symbolic link 로 넘어간다. 파일에는 junction 을 걸 수 없으므로
    symbolic link 를 쓰고, 그것도 안 되면 hard link 로 넘어간다.

    반복 실행해도 안전하다(idempotent).
      - source 가 없으면               [SKIP]
      - 올바른 링크가 이미 있으면      [OK]
      - 링크가 잘못됐거나 끊겼으면     링크만 제거 후 재생성 [FIX]
      - target 이 실제 파일/디렉터리면 건드리지 않고 [ERROR] (종료코드 1)

.EXAMPLE
    pwsh -File script\setup-agent-links.ps1
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# 현재 working directory 와 무관하게 스크립트 위치에서 project root 를 잡는다.
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).ProviderPath
# PowerShell 5.1 에는 $IsWindows 가 없다. 5.1 은 Windows 전용이므로 없으면 Windows 로 본다.
$OnWindows = if (Test-Path Variable:\IsWindows) { $IsWindows } else { $true }

# Source/Target 은 project root 기준 상대경로, Kind 는 'dir' 또는 'file'.
# 항목을 추가하려면 이 배열에만 한 줄 넣으면 된다(setup-agent-links.sh 의 LINKS 와 같이 맞출 것).
$Links = @(
    @{ Source = ".agent/skills"; Target = ".claude/skills"; Kind = "dir" }
    @{ Source = ".agent/rules";  Target = ".claude/rules";  Kind = "dir" }
    @{ Source = ".agent/agents"; Target = ".claude/agents"; Kind = "dir" }
    # MCP: Claude Code 의 공식 project-scoped 설정 위치는 프로젝트 root 의 .mcp.json 이다.
    # (.claude/mcp 같은 경로는 존재하지 않는다.) 정본을 .agent/mcp.json 에 두면 여기에 연결된다.
    @{ Source = ".agent/mcp.json"; Target = ".mcp.json"; Kind = "file" }
)

$script:HadError = $false

function Write-Status([string]$Tag, [string]$Message) {
    Write-Host ("{0,-7} {1}" -f $Tag, $Message)
}

function Join-Root([string]$Relative) {
    $native = $Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    return [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $native))
}

function Get-ItemOrNull([string]$Path) {
    # 끊어진 링크도 잡아야 하므로 Test-Path 가 아니라 Get-Item -Force 를 쓴다.
    try { return Get-Item -LiteralPath $Path -Force -ErrorAction Stop } catch { return $null }
}

function Test-HasProperty($Item, [string]$Name) {
    return ($null -ne $Item) -and ($Item.PSObject.Properties.Name -contains $Name)
}

function Test-IsLink($Item) {
    if ($null -eq $Item) { return $false }
    if ((Test-HasProperty $Item 'LinkType') -and $Item.LinkType) { return $true }
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-LinkTargetFull($Item) {
    # LinkType 에 따라 Target 이 string 이거나 string[] 이고, 상대경로일 수도 있다.
    $raw = $null
    if ((Test-HasProperty $Item 'Target') -and $Item.Target) { $raw = @($Item.Target)[0] }
    if (-not $raw) { return $null }
    if (-not [System.IO.Path]::IsPathRooted($raw)) {
        $raw = Join-Path (Split-Path -Parent $Item.FullName) $raw
    }
    return [System.IO.Path]::GetFullPath($raw)
}

function Test-PathEqual([string]$Left, [string]$Right) {
    if (-not $Left -or -not $Right) { return $false }
    $separators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $a = $Left.TrimEnd($separators)
    $b = $Right.TrimEnd($separators)
    if ($OnWindows) { return [string]::Equals($a, $b, [System.StringComparison]::OrdinalIgnoreCase) }
    return [string]::Equals($a, $b, [System.StringComparison]::Ordinal)
}

function Test-HardLinkTo([string]$LinkPath, [string]$SourcePath) {
    # hard link 는 Target 이 비어 있어 경로 비교가 안 된다. fsutil 로 같은 실체인지 확인한다.
    try {
        $entries = & fsutil.exe hardlink list $LinkPath 2>$null
        if (-not $entries) { return $false }
        $root = [System.IO.Path]::GetPathRoot($SourcePath)
        $tail = $SourcePath.Substring($root.Length)
        foreach ($entry in $entries) {
            $candidate = $entry.Trim()
            if (Test-PathEqual $candidate $SourcePath) { return $true }
            if (Test-PathEqual $candidate $tail) { return $true }
            if (Test-PathEqual $candidate ([System.IO.Path]::DirectorySeparatorChar + $tail)) { return $true }
        }
    } catch { return $false }
    return $false
}

function Remove-LinkOnly([string]$Path, [bool]$IsDirectory) {
    # 링크(reparse point) 자체만 지운다. 링크가 가리키는 정본은 건드리지 않는다.
    if ($IsDirectory) { [System.IO.Directory]::Delete($Path, $false) }
    else { [System.IO.File]::Delete($Path) }
}

function New-AgentLink([string]$TargetFull, [string]$SourceFull, [string]$Kind) {
    # 실제로 만들어진 링크 종류를 돌려준다.
    if ($Kind -eq "dir" -and $OnWindows) {
        try {
            New-Item -ItemType Junction -Path $TargetFull -Target $SourceFull | Out-Null
            return "junction"
        } catch {
            Write-Status "[WARN]" "junction 생성 실패, symbolic link 로 재시도: $($_.Exception.Message)"
        }
    }
    try {
        New-Item -ItemType SymbolicLink -Path $TargetFull -Target $SourceFull | Out-Null
        return "symlink"
    } catch {
        if ($Kind -eq "file" -and $OnWindows) {
            New-Item -ItemType HardLink -Path $TargetFull -Target $SourceFull | Out-Null
            Write-Status "[WARN]" "symbolic link 를 만들 수 없어 hard link 를 썼다(개발자 모드를 켜면 symbolic link 를 쓴다). 에디터가 파일을 통째로 교체하면 정본과 끊어질 수 있다."
            return "hardlink"
        }
        throw
    }
}

function Set-AgentLink([hashtable]$Entry) {
    $sourceRel  = $Entry.Source
    $targetRel  = $Entry.Target
    $kind       = $Entry.Kind
    $sourceFull = Join-Root $sourceRel
    $targetFull = Join-Root $targetRel

    if (-not (Test-Path -LiteralPath $sourceFull)) {
        Write-Status "[SKIP]" "$sourceRel 없음 -> $targetRel 건너뜀"
        return
    }
    if ($kind -eq "dir" -and -not (Test-Path -LiteralPath $sourceFull -PathType Container)) {
        Write-Status "[ERROR]" "$sourceRel 이 디렉터리가 아니다"
        $script:HadError = $true
        return
    }

    $parent = Split-Path -Parent $targetFull
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $existing = Get-ItemOrNull $targetFull
    if ($null -ne $existing) {
        if (-not (Test-IsLink $existing)) {
            Write-Status "[ERROR]" "$targetRel 이 실제 파일/디렉터리다. 직접 확인해 옮기거나 지운 뒤 다시 실행할 것"
            $script:HadError = $true
            return
        }

        $isDirLink = (($existing.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0)
        $linkType  = if (Test-HasProperty $existing 'LinkType') { $existing.LinkType } else { $null }

        if ($linkType -eq 'HardLink') {
            $valid = Test-HardLinkTo $targetFull $sourceFull
        } else {
            $valid = (Test-Path -LiteralPath $targetFull) -and (Test-PathEqual (Get-LinkTargetFull $existing) $sourceFull)
        }

        if ($valid) {
            Write-Status "[OK]" "$targetRel -> $sourceRel ($linkType)"
            return
        }

        Remove-LinkOnly $targetFull $isDirLink
        $created = New-AgentLink $targetFull $sourceFull $kind
        Write-Status "[FIX]" "$targetRel -> $sourceRel ($created, 잘못된 링크 재생성)"
        return
    }

    $created = New-AgentLink $targetFull $sourceFull $kind
    Write-Status "[LINK]" "$targetRel -> $sourceRel ($created)"
}

Write-Host "project root: $ProjectRoot"
Write-Host ""
foreach ($entry in $Links) {
    # 한 항목이 실패해도 나머지는 계속 처리한다.
    try {
        Set-AgentLink $entry
    } catch {
        Write-Status "[ERROR]" "$($entry.Target): $($_.Exception.Message)"
        $script:HadError = $true
    }
}
Write-Host ""
if ($script:HadError) {
    Write-Host "실패한 항목이 있다. 위 [ERROR] 를 확인할 것." -ForegroundColor Red
    exit 1
}
Write-Host "완료."
