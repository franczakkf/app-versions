#Requires -Version 7.0
# Local gate, run by .githooks/pre-push: secret scan first, then the project's tests.
& (Join-Path $PSScriptRoot 'tools\secret-scan.ps1')
if ($LASTEXITCODE -ne 0) { exit 1 }
# Add the project's tests here and exit 1 when they fail, e.g.:
# $r = Invoke-Pester -Path (Join-Path $PSScriptRoot 'tests') -PassThru; exit ([int]($r.Result -ne 'Passed'))
exit 0
