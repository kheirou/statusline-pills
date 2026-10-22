[Console]::OutputEncoding = [Text.Encoding]::UTF8
$j = [Console]::In.ReadToEnd() | ConvertFrom-Json
$model = $j.model.display_name
$dir = Split-Path -Leaf $j.workspace.current_dir
$branch = git -C $j.workspace.current_dir branch --show-current 2>$null
$pct = $j.context_window.used_percentage
if ($null -eq $pct) { $pct = 0 }
$cost = [math]::Round([double]$j.cost.total_cost_usd, 2)
$e = [char]27
$capL = [char]0xE0B6; $capR = [char]0xE0B4
$ico = @{ folder = [char]0xF07B; branch = [char]0xE0A0 }
function Bar($v, $max, $n = 8) {
    $f = [math]::Min($n, [math]::Max(0, [int][math]::Round($n * $v / $max)))
    ('━' * $f) + ('╌' * ($n - $f))
}
function Fg($c) { "$e[38;5;${c}m" }
$W = Fg 252; $D = "$e[2m"; $ND = "$e[22m"
$bgCtx = if ($pct -ge 70) { "66;34;34" } elseif ($pct -ge 40) { "62;54;30" } else { "34;50;38" }
# Powerline segments: @(background-256-color, text)
$parts = @(
    ,@("48;52;74", "🤖 $model")
    ,@("30;54;58", "$($ico.folder) $dir" + $(if ($branch) { "  $(Fg 213)$($ico.branch) $branch$W" }))
    ,@($bgCtx, "🧠  $(Bar $pct 100) $([int]$pct)%  `$$cost")
)

# Prompt cache (what the prompt-cache-control mod showed): hit rate of the last
# main-loop request and when its 1h cache lapses.
try {
    $usage = $null
    if ($j.transcript_path -and (Test-Path $j.transcript_path)) {
        $tail = Get-Content $j.transcript_path -Tail 200
        for ($i = $tail.Count - 1; $i -ge 0 -and -not $usage; $i--) {
            if ($tail[$i] -notmatch '"cache_read_input_tokens"') { continue }
            $r = $tail[$i] | ConvertFrom-Json
            if ($r.type -eq 'assistant' -and -not $r.isSidechain -and $r.message.usage) { $usage = $r }
        }
    }
    if ($usage) {
        $u = $usage.message.usage
        $total = [double]$u.cache_read_input_tokens + $u.cache_creation_input_tokens + $u.input_tokens
        $hit = if ($total -gt 0) { [int](100 * $u.cache_read_input_tokens / $total) } else { 0 }
        $until = ([datetime]$usage.timestamp).ToLocalTime().AddHours(1)
        if ($until -gt (Get-Date)) {
            $hc = if ($hit -ge 80) { 32 } elseif ($hit -ge 40) { 33 } else { 31 }
            $parts += ,@("30;44;62", "$(Fg @{32=108;33=179;31=167}[$hc])💾 $hit%$W $D→$($until.ToString('HH:mm'))$ND")
        } else {
            $parts += ,@("30;44;62", "$D💾 cold$ND")
        }
    }
} catch {}

# Subagent tuner mode and saved default, from the mod's store.
try {
    $store = Get-ChildItem "$HOME/.claude/plugins/store/subagent-tuner_*.json" -ErrorAction Stop | Select-Object -First 1
    $t = Get-Content $store.FullName -Raw | ConvertFrom-Json
    $def = if ($t.saved) { " $($t.saved.model ?? '-')/$($t.saved.effort ?? '-')" } else { '' }
    $parts += ,@("60;44;58", "🎛  $($t.mode)$def")
} catch {}

# Pet (inline), real data from the pet skill store.
try {
    $ps = Get-ChildItem "$HOME/.claude/plugins/store/pet_*.json" -ErrorAction Stop | Select-Object -First 1
    $p = (Get-Content $ps.FullName -Raw | ConvertFrom-Json).pet
    $lvl = [math]::Floor([math]::Sqrt($p.xp / 10))
    $nextXp = 10 * [math]::Pow($lvl + 1, 2)
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $mood = [math]::Min($p.mood, [math]::Max(30, $p.mood - [math]::Floor(($now - $p.at) / 600000)))
    $moodEmoji = if ($mood -ge 70) { '😸' } elseif ($mood -ge 35) { '😺' } else { '😿' }
    $mc = if ($mood -ge 70) { 32 } elseif ($mood -ge 35) { 33 } else { 31 }
    $stage = if ($lvl -ge 10) { 'legend' } elseif ($lvl -ge 6) { 'adult' } elseif ($lvl -ge 3) { 'kid' } elseif ($lvl -ge 1) { 'baby' } else { 'egg' }
    $stageEmoji = switch ($stage) { 'egg' {'🥚'} 'baby' {'🐱'} 'kid' {'🐈'} 'adult' {'🐆'} default {'🦁'} }
    $face = "$stageEmoji$moodEmoji"
    $age = [TimeSpan]::FromMilliseconds($now - $p.born)
    $ageTxt = if ($age.TotalDays -ge 1) { "$([int]$age.TotalDays)d" } else { "$([int]$age.TotalHours)h" }
    $moodFg = Fg @{32=108;33=179;31=167}[$mc]
    $parts += ,@("54;36;56", "$(Fg 218)$face ⭐ $lvl $stage$W $D$(Bar ($p.xp - 10 * $lvl * $lvl) ($nextXp - 10 * $lvl * $lvl))$ND ${D}•${ND} 💗 $mood${D} •${ND} 📝 $($p.edits) ${D}•${ND} 🔀 $($p.commits) ${D}•${ND} 🧪 $($p.tests) ${D}•${ND} ❌ $($p.fails) ${D}•${ND} 🎂 $ageTxt")
} catch {}

$out = ''
foreach ($part in $parts) {
    $bg = $part[0]
    $out += "$e[38;2;${bg}m$capL$e[48;2;${bg}m$W $($part[1]) $e[0m$e[38;2;${bg}m$capR$e[0m "
}
$out.TrimEnd()
