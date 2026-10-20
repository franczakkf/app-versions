#Requires -Version 7.0
# Secret scan of local commits that are on no remote yet (called first by check.ps1, so by pre-push).
# Managed by the project template (.ai-template.json): change it there, not here.
$repo = & git -C $PSScriptRoot rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -or -not $repo) { Write-Host 'secret-scan: not inside a git repository'; exit 1 }

$exe = Get-Command gitleaks -CommandType Application -ErrorAction Ignore | Select-Object -First 1 -ExpandProperty Source
if (-not $exe) {
    # A per-user winget install is missing from PATH in shells opened before the install.
    $exe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gitleaks.Gitleaks_*\gitleaks.exe" -ErrorAction Ignore |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $exe) { Write-Host 'secret-scan: gitleaks not found. Install: winget install Gitleaks.Gitleaks --scope user'; exit 1 }

# Every local branch minus everything any remote has: covers pushing any branch, new branches
# without upstream, and never rescans published history. No remote at all = all local commits.
$gl = @('git', $repo, '--redact', '--no-banner', '--log-opts=--branches --not --remotes')
$config = Join-Path $repo '.gitleaks.toml'
if (Test-Path -LiteralPath $config -PathType Leaf) { $gl += @('--config', $config) }
& $exe @gl
exit $LASTEXITCODE
