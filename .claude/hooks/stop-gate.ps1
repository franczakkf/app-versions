#Requires -Version 7.4
<#
.SYNOPSIS
    Claude Code Stop hook: runs `check.ps1 -Quick` when uncommitted files with -Extensions exist.
.DESCRIPTION
    No -Extensions = no-op. A failure prints {"decision":"block","reason":...} and exits 0
    (code.claude.com/docs/en/hooks, Stop). At most -MaxBlocks blocks per user turn.
#>
[CmdletBinding()]
param(
    # File extensions without the dot, e.g. py, toml; set in .claude/settings.json per project.
    [string[]]$Extensions = @(),
    [string]$RepoRoot = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($PSScriptRoot)),
    [string]$GateScript,
    [int]$MaxBlocks = 2,
    [int]$MaxLines = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$raw = if ([Console]::IsInputRedirected) { [Console]::In.ReadToEnd() } else { '' }
# Split on commas too: `pwsh -File hook.ps1 -Extensions py,toml` binds one string, not an array.
$Extensions = @($Extensions -split ',' | ForEach-Object { $_.Trim().TrimStart('.') } | Where-Object { $_ })
if ($Extensions.Count -eq 0) { exit 0 }
# true = the agent is continuing after a block in this turn; the gate still runs so the fix is
# verified, and the per-turn count stops a loop. Regex, not ConvertFrom-Json: ~150 ms per stop.
$continuing = $raw -match '"stop_hook_active"\s*:\s*true\b'

# .NET file calls instead of cmdlets up to the gate: the first Resolve-Path / ConvertFrom-Json
# loads a module, 150-170 ms each on every stop (measured); paths are absolute before use.
$RepoRoot = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($RepoRoot)
# -z: quoted paths with spaces would not end in the extension; all: a new folder is one `dir/` entry.
$status = (git -C $RepoRoot status --porcelain=v1 -z --untracked-files=all 2>$null) -join "`0"
if ($LASTEXITCODE -ne 0) { exit 0 }

# Under .git so the counter is never committed; a linked worktree has a `gitdir: <path>` file.
$gitDir = [IO.Path]::Combine($RepoRoot, '.git')
if ([IO.File]::Exists($gitDir)) {
    $gitDir = ([IO.File]::ReadAllLines($gitDir)[0] -replace '^gitdir:\s*', '').Trim()
    $gitDir = [IO.Path]::GetFullPath($gitDir, $RepoRoot)
}
# One counter per session: parallel sessions in one checkout must not share the block limit.
$session = if ($raw -match '"session_id"\s*:\s*"([^"]+)"') { '-' + ($Matches[1] -replace '[^A-Za-z0-9-]', '') } else { '' }
$counterPath = [IO.Path]::Combine($gitDir, "stop-gate-blocks$session")
if (-not $continuing) {
    [IO.File]::Delete($counterPath)
    # Counters of ended sessions are never reset by their own session.
    if ([IO.Directory]::Exists($gitDir)) {
        foreach ($old in [IO.Directory]::GetFiles($gitDir, 'stop-gate-blocks-*')) {
            if ([IO.File]::GetLastWriteTimeUtc($old) -lt [DateTime]::UtcNow.AddDays(-1)) { [IO.File]::Delete($old) }
        }
    }
}

$pattern = '\.(' + (($Extensions | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')$'
$changed = @($status -split "`0" | Where-Object { $_ -match $pattern })
if ($changed.Count -eq 0) {
    [IO.File]::Delete($counterPath)
    exit 0
}

$blocks = 0
if ([IO.File]::Exists($counterPath)) {
    [void][int]::TryParse([IO.File]::ReadAllText($counterPath).Trim(), [ref]$blocks)
}
if ($blocks -ge $MaxBlocks) { exit 0 }

if (-not $GateScript) { $GateScript = [IO.Path]::Combine($RepoRoot, 'check.ps1') }
# The running pwsh, not a PATH lookup: `pwsh` may resolve to a WindowsApps alias.
$output = & ([Environment]::ProcessPath) -NoProfile -NonInteractive -File $GateScript -Quick 2>&1 |
    ForEach-Object { ("$_" -replace '\x1b\[[0-9;]*m', '').TrimEnd() } |
    Where-Object { $_ }
$code = $LASTEXITCODE

if ($code -eq 0) {
    [IO.File]::Delete($counterPath)
    exit 0
}

[IO.File]::WriteAllText($counterPath, [string]($blocks + 1))
$lines = @($output)
$kinds = ($Extensions | ForEach-Object { "*.$_" }) -join ', '
# Names the step to re-run: a live headless run refused a nested `pwsh -File ./check.ps1`.
$reason = @(
    "Stop hook: quick gate (check.ps1 -Quick) failed with uncommitted $kinds changes."
    'Fix it, then verify by re-running the failing check named in the output below.'
    'If a flagged file was not changed by you in this turn, report it to the owner instead of editing it.'
    ''
    $lines | Select-Object -First $MaxLines
)
if ($lines.Count -gt $MaxLines) {
    $reason += "... $($lines.Count - $MaxLines) more lines; re-run the failing check for the full output."
}
# Only the JSON object on stdout, or Claude Code does not read it as a decision.
[Console]::Out.Write((@{ decision = 'block'; reason = ($reason -join "`n") } | ConvertTo-Json -Compress))
exit 0
