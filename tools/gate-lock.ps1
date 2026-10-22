#Requires -Version 7.0
<#
.SYNOPSIS
    Runs a gate under a machine-wide lock: pwsh -NoProfile -File tools/gate-lock.ps1 ./check.ps1 [arguments].
.DESCRIPTION
    One heavy gate at a time: parallel test suites on this 4-core machine pushed each other past their timeouts.
    Env: PROJEKTY_AI_GATE_LOCK_TIMEOUT_MIN (default 180); PROJEKTY_AI_GATE_LOCK_NAME and _POLL_SEC for tests.
    Managed by the project template (.ai-template.json): change it there, not here.
#>
# $args, not param(): a gate argument such as -T would otherwise bind to a parameter of this script.
if ($args.Count -lt 1) { Write-Host 'gate-lock: usage: gate-lock.ps1 <gate.ps1> [arguments]'; exit 2 }
$gate = "$($args[0])"
$gateArgs = @($args | Select-Object -Skip 1)
$pwsh = (Get-Process -Id $PID).Path
# The hook locks and check.ps1 asks again: the holder's children run at once instead of deadlocking.
if ($env:PROJEKTY_AI_GATE_LOCK) { & $pwsh -NoProfile -File $gate @gateArgs; exit $LASTEXITCODE }

$name = if ($env:PROJEKTY_AI_GATE_LOCK_NAME) { $env:PROJEKTY_AI_GATE_LOCK_NAME } else { 'Global\ProjektyAI-Gate' }
$timeout = if ($env:PROJEKTY_AI_GATE_LOCK_TIMEOUT_MIN) { [double]$env:PROJEKTY_AI_GATE_LOCK_TIMEOUT_MIN } else { 180 }
$poll = if ($env:PROJEKTY_AI_GATE_LOCK_POLL_SEC) { [double]$env:PROJEKTY_AI_GATE_LOCK_POLL_SEC } else { 60 }
$info = Join-Path ([IO.Path]::GetTempPath()) "$($name -replace '[\\/:]', '-').json"

function Get-Holder {
    # The mutex has no owner data, so the holder leaves its PID, gate and start time next to it.
    try { $h = [IO.File]::ReadAllText($info) | ConvertFrom-Json; "PID $($h.pid), $($h.gate), since $($h.started)" }
    catch { 'holder unknown' }
}

try { $mutex = [Threading.Mutex]::new($false, $name) }
catch {
    # E.g. a mutex created by an elevated shell is not open to this one: the lock is no check, so run.
    Write-Host "gate-lock: lock unavailable ($($_.Exception.Message)); running without it"
    # Marked as held anyway, or check.ps1 would call this script again, endlessly.
    $env:PROJEKTY_AI_GATE_LOCK = 'none'
    & $pwsh -NoProfile -File $gate @gateArgs; exit $LASTEXITCODE
}
$held = $false
$code = 1
$start = [DateTime]::UtcNow
try {
    # Stale-lock rule: the OS releases the mutex of a process that died, and the next waiter gets it
    # as "abandoned"; only a live holder blocks, and only until the timeout.
    $take = { param([TimeSpan]$Wait)
        try { $mutex.WaitOne($Wait) }
        catch [Threading.AbandonedMutexException] { Write-Host 'gate-lock: the previous gate died holding the lock; taking it over'; $true }
    }
    # The grace seconds also let a holder that just started write its PID for the message below.
    $held = & $take ([TimeSpan]::FromSeconds(2))
    if (-not $held) {
        Write-Host "gate-lock: another gate is running ($(Get-Holder)); waiting up to $timeout min"
        while (-not $held) {
            $left = $timeout - ([DateTime]::UtcNow - $start).TotalMinutes
            if ($left -le 0) {
                Write-Host "gate-lock: gave up after $timeout min, lock still held ($(Get-Holder)): stop that gate if it hangs, then run again"
                exit 1
            }
            $held = & $take ([TimeSpan]::FromSeconds([Math]::Max(0.1, [Math]::Min($poll, $left * 60))))
            if (-not $held) { Write-Host "gate-lock: still waiting, $([int]([DateTime]::UtcNow - $start).TotalMinutes) min" }
        }
        Write-Host "gate-lock: lock taken after $([Math]::Round(([DateTime]::UtcNow - $start).TotalMinutes, 1)) min"
    }
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($gate)
    [IO.File]::WriteAllText($info, (@{ pid = $PID; gate = $full; started = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') } | ConvertTo-Json -Compress))
    $env:PROJEKTY_AI_GATE_LOCK = "$PID"
    & $pwsh -NoProfile -File $gate @gateArgs
    $code = $LASTEXITCODE
}
finally {
    if ($held) {
        if ((Get-Holder) -like "PID $PID,*") { Remove-Item -LiteralPath $info -Force -ErrorAction Ignore }
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
exit $code
