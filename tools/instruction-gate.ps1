#Requires -Version 7.0
# Instruction gate (run by check.ps1 after the secret scan; managed by the template): core blocks match .ai-template.json,
# and AGENTS.md, CLAUDE.md, .claude/rules/**/*.md grow by at most +10 lines against the remote default branch, linted.
param([int]$MaxGrowth = 10, [int]$MaxLength = 160)
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-GateCoreHash([AllowEmptyString()][string]$Text) {
    # Same result as Get-CoreHash in the core-guard hook library (a test compares them); duplicated
    # because template scripts must run on their own. $null = no blocks, 'invalid' = broken markers.
    $t = $Text.Replace("`r`n", "`n"); $parts = [System.Collections.Generic.List[string]]::new(); $open = -1
    foreach ($m in [regex]::Matches($t, '<!--\s*core:(start|end)\s*-->')) {
        if ($m.Groups[1].Value -eq 'start') { if ($open -ge 0) { return 'invalid' }; $open = $m.Index + $m.Length }
        else { if ($open -lt 0) { return 'invalid' }; $parts.Add($t.Substring($open, $m.Index - $open)); $open = -1 }
    }
    if ($open -ge 0) { return 'invalid' }
    if ($parts.Count -eq 0) { return $null }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join "`n<!-- core -->`n"))
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

$IncludeSpec = @(':(glob,icase)**/AGENTS.md', ':(glob,icase)**/CLAUDE.md', ':(glob)**/.claude/rules/**/*.md')

function Test-ExcludeAllowed([object]$Entry) {
    # First filter only: a string of plain path characters, first segment a literal directory, no '.'/'..' segments.
    # Git has the final word (Get-DroppedRootFile), since it normalises paths, and on Windows '\' is a separator.
    if ($Entry -isnot [string] -or $Entry -cnotmatch '^[A-Za-z0-9_. */-]+$') { return $false }
    $seg = $Entry.Split('/')
    if ($seg.Count -lt 2 -or $seg[0] -eq '' -or $seg[0].Contains('*')) { return $false }
    -not @($seg | Where-Object { $_ -in '.', '..' }).Count
}

function Get-DroppedRootFile([string]$Repo, [string[]]$Include, [string[]]$Exclude) {
    # Root AGENTS.md/CLAUDE.md that git lists without the exclusions but not with them; throws on a git error.
    $list = {
        param($Extra)
        $out = @(& git -C $Repo -c core.quotepath=off ls-files -co --exclude-standard -- @Include @Extra 2>$null)
        if ($LASTEXITCODE) { throw "git ls-files failed (exit $LASTEXITCODE)" }
        @($out | Where-Object { $_ -match '(?i)^(AGENTS|CLAUDE)\.md$' })
    }
    $all = & $list @()
    $kept = & $list @($Exclude | ForEach-Object { ":(exclude,glob)$_" })
    @($all | Where-Object { $_ -cnotin $kept })
}

$repo = & git -C $PSScriptRoot rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -or -not $repo) { Write-Host 'instruction-gate: not inside a git repository'; exit 1 }
$problems = [System.Collections.Generic.List[string]]::new()

# Vendored files (e.g. a third-party skill's AGENTS.md) go to "gate-exclude"; "core" holds the approved core hashes.
$exclude = @(); $core = [ordered]@{}; $badExclude = $false
$cfg = Join-Path $repo '.ai-template.json'
if ([IO.File]::Exists($cfg)) {
    try { $data = [IO.File]::ReadAllText($cfg, $utf8) | ConvertFrom-Json -AsHashtable -ErrorAction Stop }
    catch { $data = $null }
    if ($data -isnot [System.Collections.IDictionary]) { Write-Host 'instruction-gate: unreadable .ai-template.json'; exit 1 }
    if ($null -ne $data['gate-exclude']) {
        # No pipeline and no if-expression: both unroll arrays, which would flatten a nested array into valid entries.
        $items = $data['gate-exclude']
        if ($items -isnot [System.Collections.IList]) { $items = @($items) }
        for ($i = 0; $i -lt $items.Count; $i++) {
            $e = $items[$i]
            if (Test-ExcludeAllowed $e) { $exclude += $e; continue }
            $badExclude = $true
            $problems.Add("gate-exclude $(ConvertTo-Json -InputObject $e -Compress) odrzucony: wpis to tekst ze znaków [A-Za-z0-9_. */-], zaczyna się dosłowną nazwą katalogu i '/', bez segmentów '.' i '..'")
        }
    }
    if ($data['core'] -is [System.Collections.IDictionary]) { $core = $data['core'] }
}
if (-not $badExclude -and $exclude.Count) {
    try {
        foreach ($g in $exclude) {
            foreach ($f in Get-DroppedRootFile $repo $IncludeSpec @($g)) { $badExclude = $true; $problems.Add("gate-exclude '$g' w .ai-template.json wyklucza główny $f") }
        }
        if (-not $badExclude) {
            foreach ($f in Get-DroppedRootFile $repo $IncludeSpec $exclude) { $badExclude = $true; $problems.Add("gate-exclude w .ai-template.json razem wykluczają główny $f") }
        }
    }
    catch { Write-Host "instruction-gate: $($_.Exception.Message) while checking gate-exclude"; exit 1 }
}

# Native output is decoded with the console encoding; force UTF-8 so Polish text and paths survive.
function Invoke-GitText([string[]]$GitArgs) {
    $enc = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = $utf8; @(& git -C $repo -c core.quotepath=off @GitArgs) } finally { [Console]::OutputEncoding = $enc }
}

# Core check: the same rule and paths as S9 (Test-InstructionPath), here so that every agent's push runs it
# (Codex has no Claude hooks). Both the working tree and HEAD: the push sends commits, not the tree.
$instructionPath = '(?i)(^|/)(AGENTS|CLAUDE)\.md$|(^|/)\.claude/rules/.+\.md$|(^|/)(home|\.claude)/docs/[^/]+\.md$'
function Test-CoreSet([string]$Label, [string[]]$Files, $Core, [scriptblock]$Read) {
    foreach ($rel in @(@($Files | Where-Object { $_ -match $instructionPath }) + @($Core.Keys) | Select-Object -Unique)) {
        $text = & $Read $rel
        if ($null -eq $text) { if ($Core.Contains($rel)) { $problems.Add("$Label brak $rel (ma zapisany hash core)") }; continue }
        $hash = Get-GateCoreHash $text
        if ($hash -eq 'invalid') { $problems.Add("$Label uszkodzone znaczniki core w $rel") }
        elseif ($hash -ne $Core[$rel]) { $problems.Add("$Label blok core w $rel różni się od zatwierdzonego: po akceptacji właściciela uruchom Approve-CoreChange.ps1 -Path $rel -Apply i zacommituj") }
    }
}
$listed = Invoke-GitText @('ls-files', '-co', '--exclude-standard')
if ($LASTEXITCODE) { Write-Host 'instruction-gate: git ls-files failed, core blocks not checked'; exit 1 }
Test-CoreSet '[drzewo robocze]' $listed $core {
    param($rel)
    $full = Join-Path $repo $rel
    if ([IO.File]::Exists($full)) { [IO.File]::ReadAllText($full, $utf8) }
}
& git -C $repo rev-parse --verify --quiet HEAD *> $null
if ($LASTEXITCODE -eq 0) {
    function Get-HeadText([string]$Rel) {
        # Whole blob as UTF-8: native output splits on a lone CR too, so the hash would differ from the tree's.
        $psi = [Diagnostics.ProcessStartInfo]::new('git')
        foreach ($a in '-C', $repo, 'cat-file', 'blob', "HEAD:$Rel") { $psi.ArgumentList.Add($a) }
        $psi.RedirectStandardOutput = $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = $utf8
        $psi.UseShellExecute = $false
        $p = [Diagnostics.Process]::Start($psi)
        $errTask = $p.StandardError.ReadToEndAsync()
        $text = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit(); $null = $errTask.GetAwaiter().GetResult()
        if ($p.ExitCode) { return $null }
        $text
    }
    $headCore = [ordered]@{}
    $headCfg = Get-HeadText '.ai-template.json'
    if ($null -ne $headCfg) {
        try { $hd = $headCfg | ConvertFrom-Json -AsHashtable -ErrorAction Stop } catch { $hd = $null }
        if ($hd -isnot [System.Collections.IDictionary]) { $problems.Add('[HEAD] nieczytelny .ai-template.json') }
        elseif ($hd['core'] -is [System.Collections.IDictionary]) { $headCore = $hd['core'] }
    }
    $headFiles = Invoke-GitText @('ls-tree', '-r', '--name-only', 'HEAD')
    if ($LASTEXITCODE) { Write-Host 'instruction-gate: git ls-tree failed, core blocks at HEAD not checked'; exit 1 }
    Test-CoreSet '[HEAD]' $headFiles $headCore { param($rel) Get-HeadText $rel }
}

$summary = $null
$remotes = @(& git -C $repo remote)
$remote = if ('origin' -in $remotes) { 'origin' } else { $remotes | Select-Object -First 1 }
$target = if ($remote) { & git -C $repo symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>$null }
if ($remote -and -not $target) {
    # origin/HEAD is unset when the repo was created locally and pushed later.
    $target = foreach ($b in 'main', 'master') {
        & git -C $repo show-ref --verify --quiet "refs/remotes/$remote/$b"
        if ($LASTEXITCODE -eq 0) { "$remote/$b"; break }
    }
}
$base = if ($target) { & git -C $repo merge-base HEAD $target 2>$null }
if ($badExclude) { $summary = 'growth skipped: fix gate-exclude' }
elseif (-not $remote) { $summary = 'no remote, growth skipped' }
elseif (-not $target) { $summary = "no default branch on $remote, growth skipped" }
elseif (-not $base) { $summary = "no merge-base with $target, growth skipped" }
else {
    $spec = $IncludeSpec + @($exclude | ForEach-Object { ":(exclude,glob)$_" })
    $diff = Invoke-GitText (@('diff', '-U0', '--no-color', '--no-ext-diff', $base, 'HEAD', '--') + $spec)
    if ($LASTEXITCODE) { Write-Host 'instruction-gate: git diff failed'; exit 1 }

    $filler = '\b(comprehensive|robust|seamless(ly)?|leverag(e|es|ed|ing)|cutting-edge|state-of-the-art|it is worth noting|it''s worth noting)\b|' +
        '\b(kompleksow\w*|solidn\w*|warto zauważyć|warto podkreślić|warto nadmienić|należy zauważyć)\b'
    $history = '\b(added on|previously|as of|dodano|poprzednio|wcześniej)\b|\b(19|20)\d\d-\d\d-\d\d\b'
    $marker = '^\s*<!--\s*core:(start|end)\s*-->\s*$'
    $added = 0; $removed = 0; $file = ''; $header = $false
    foreach ($line in $diff) {
        # File headers run from 'diff --git' to the first hunk; a removed '-- x' line must not look like one.
        if ($line.StartsWith('diff --git ')) { $header = $true; continue }
        if ($line.StartsWith('@@')) { $header = $false; continue }
        if ($header) { if ($line.StartsWith('+++ ')) { $file = $line -replace '^\+\+\+ (b/)?', '' }; continue }
        # Core markers wrap existing rules; counting them would punish protecting a rule.
        if ($line -match '^[+-]' -and $line.Substring(1) -match $marker) { continue }
        if ($line.StartsWith('-')) { $removed++; continue }
        if (-not $line.StartsWith('+')) { continue }
        $added++
        $text = $line.Substring(1)
        # Quoted words and code spans are examples or identifiers, not prose.
        $prose = $text -replace '`[^`]*`', '' -replace '"[^"]*"', '' -replace '„[^”]*”', '' -replace '“[^”]*”', ''
        $short = if ($text.Length -gt 70) { $text.Substring(0, 70) + '…' } else { $text }
        if ($prose -match $filler) { $problems.Add("${file}: wypełniacz '$($Matches[0])': $short") }
        if ($prose -match $history) { $problems.Add("${file}: data lub historia '$($Matches[0])' (to należy do git log): $short") }
        # Table rows cannot wrap, so only prose lines have a length limit.
        if ($text.Length -gt $MaxLength -and -not $text.TrimStart().StartsWith('|')) { $problems.Add("${file}: linia ma $($text.Length) > $MaxLength znaków: $short") }
    }
    $growth = $added - $removed
    if ($growth -gt $MaxGrowth) { $problems.Insert(0, "pliki instrukcji urosły o $growth linii (limit +$MaxGrowth wobec $target): skondensuj") }
    $summary = "wzrost $growth linii wobec $target"
}
if ($exclude.Count) { $summary += '; wykluczone: ' + ($exclude -join ', ') }

if ($problems.Count) {
    Write-Host "instruction-gate: FAIL ($summary)"
    $problems | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host "instruction-gate: OK (core: $($core.Count) plików; $summary)"
exit 0
