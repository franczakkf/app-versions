#Requires -Version 7.0
# Local gate, run by .githooks/pre-push: secret scan and instruction gate first, then the project's tests.
# Fail closed: "&" on a missing script leaves $LASTEXITCODE as it was, so each script is checked first.
foreach ($name in @(
        'secret-scan.ps1'
        'instruction-gate.ps1'
    )) {
    $script = Join-Path $PSScriptRoot "tools\$name"
    if (-not (Test-Path -LiteralPath $script)) { Write-Error "Missing $script"; exit 1 }
    & $script
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
# Add the project's tests here and exit 1 when they fail, e.g.:
# $r = Invoke-Pester -Path (Join-Path $PSScriptRoot 'tests') -PassThru; exit ([int]($r.Result -ne 'Passed'))
exit 0
