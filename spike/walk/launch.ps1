# Spike (#14): one command starts the walk spike: an ENet host (not a player, it watches from above) and two
# first-person clients on this machine (127.0.0.1), each with its own log in tools\out\logs\walk-spike\. From the
# project root:
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1                   # three windows; play, close by hand
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Seconds 15 -Shots
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Headless -Seconds 15 -KillClientAfter 7
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Headless -Seconds 12 -Cheat
# In a client window: click to capture the mouse, move the mouse to look, WASD to walk, Esc to release the mouse.
# Both clients also walk in circles by themselves (--auto) while no key is held.
# With -Seconds every process quits by itself and the script checks the logs: both clients are placed and move, the
# host accepts moves from both, each client sees the other one move, nobody logs an error, and no honest client is
# ever rejected or corrected. -Cheat makes client 2 teleport and then speed; the host must reject both and correct
# client 2, and client 1 must stay unrejected. -KillClientAfter N hard-kills client 2 as in spike\net\launch.ps1.
# -Shots saves each window as a PNG next to its log (windowed only) after -ShotAt seconds (default 6). -TickHz and -InterpTicks set the snapshot rate
# and the interpolation delay. -LatencyMs, -JitterMs and -Loss make every process delay and drop incoming moves and
# snapshots like a real network (one way; the round trip is twice that). Exit code 0 means PASS.
#
# Proximity voice (#15): -Voice tone makes both clients speak a tone (440 and 660 Hz); -Voice mic makes client 1
# speak into the microphone and client 2 a tone (one machine has one microphone). -Cutoff sets the host's delivery
# cutoff and the players' max_distance (default 8 m; the -Seconds checks want some time beyond it, so use 5).
# -Listen 1 or 2 mutes the other client's output, so you hear the game from one client only; -Listen 0 mutes both
# (the default with -Seconds, so a check run is silent; the levels are still measured). Use headphones.
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Voice mic -Listen 1      # hear client 2's tone
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Voice mic -Listen 2      # hear your own voice
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Headless -Seconds 20 -Voice tone -Cutoff 5
# With -Seconds and -Voice the script also checks: the host relays each client's voice to the other, never beyond
# the cutoff, and culls it beyond; almost every frame arrives; each listener's Voice bus is louder near than far
# and silent beyond the cutoff (client 2's level is checked only for a tone speaker).
# Two machines on one LAN: on the first, -Lan starts the host (listening on every address) and client 1 and prints
# this machine's addresses; on the second, -Join <address> starts client 2 only. With -Voice mic each machine's
# client speaks into its own microphone. Neither checks logs. The two machines must reach each other: a router with
# client (AP) isolation keeps a Wi-Fi laptop from a wired PC (#15: both on Wi-Fi worked).
# Godot 4.7.2 takes only mono or stereo microphones; a laptop's 4-channel microphone array floods the log with
# "unsupported channel count" and freezes. -ListMics prints the microphones (starting none); -MicDevice "<name>"
# picks one, e.g. a headset's.
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -ListMics
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Join 192.168.0.138 -Voice mic -MicDevice "Headset (...)"
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Lan -Voice mic
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Join 192.168.1.23 -Voice mic
#
# Latency (#16). Every voice run logs every 25th frame at the speaker, the host and the listener on the system clock
# (1 ms steps); with -Seconds on one machine the script prints each leg: the frame's age at encoding, up to the host,
# down to the listener, the jitter buffer's reorder wait, the playback queue ahead of it and the output driver's
# latency. -Latency measures mouth to ear through the air: client 2 speaks nothing and clicks through its loudspeaker
# every -ClickEvery seconds; client 1's microphone hears each click, then again after the whole voice path (client 2
# plays client 1's voice). The gap is the latency with the audio devices included. It needs a loudspeaker the
# microphone hears (no headphones), and -Cutoff defaults to 30 so the relayed click stays loud; client 2's Voice bus
# is raised by -EchoGainDb (default 18) and open only for 0.7 s after each click, so the loop cannot howl. -NoDenoise turns
# RNNoise off. Client 1's raw microphone goes to client1-mic.wav next to its log. -Analyze prints the latency
# summary of the logs already there, starting nothing (after a -Lan / -Join run, closed by hand or with -Seconds).
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Seconds 40 -Latency
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Lan -Latency -Seconds 60        # PC: host, mic
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Join <PC address> -Latency -Seconds 50  # laptop
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Analyze
# -Bench runs spike\voice\codec_bench.gd on this machine: the CPU cost of encoding and decoding one voice stream.
#   powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Bench
param(
    [switch]$Headless,
    [int]$Seconds = 0,
    [int]$KillClientAfter = 0,
    [switch]$Cheat,
    [switch]$Shots,
    [double]$TickHz = 20,
    [double]$InterpTicks = 2,
    [double]$LatencyMs = 0,
    [double]$JitterMs = 0,
    [double]$Loss = 0,
    [double]$ShotAt = 6,
    [int]$Port = 24560,
    [ValidateSet('off', 'mic', 'tone')][string]$Voice = 'off',
    [double]$Cutoff = 8,
    [ValidateSet(-1, 0, 1, 2)][int]$Listen = -1,
    [switch]$Lan,
    [string]$Join = '',
    [string]$Godot = '',
    [string]$MicDevice = '',
    [switch]$ListMics,
    [switch]$Latency,
    [double]$ClickEvery = 2.5,
    [double]$EchoGainDb = 18,
    [switch]$NoDenoise,
    [switch]$Analyze,
    [switch]$Bench
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Logs = Join-Path $Root 'tools\out\logs\walk-spike'
$Scene = 'res://spike/walk/walk_spike.tscn'
$CheatTeleportAt = 4
$CheatSpeedAt = 6
$MicWav = Join-Path $Logs 'client1-mic.wav'

# The q-quantile of some numbers (0.5: the median), NaN for none.
function Get-Stat([double[]]$Values, [double]$Q) {
    if (-not $Values -or $Values.Count -eq 0) { return [double]::NaN }
    $sorted = @($Values | Sort-Object)
    return $sorted[[math]::Min($sorted.Count - 1, [int][math]::Floor($Q * $sorted.Count))]
}
function Fmt([double]$Ms) { if ([double]::IsNaN($Ms)) { '-' } else { $Ms.ToString('0.0', [cultureinfo]::InvariantCulture) } }

# Latency (#16) from the logs in $Dir: prints the legs of every speaker->listener direction, the acoustic
# mouth-to-ear delays and the CPU times. Returns @{ Clicks; Echoes; Timed } for the checks.
function Show-Latency([string]$Dir) {
    $logs = @{}
    foreach ($n in @('host', 'client1', 'client2')) {
        $p = Join-Path $Dir "$n.log"
        $logs[$n] = if (Test-Path $p) { @(Get-Content $p) } else { @() }
    }
    $sends = @{}
    $hostSeen = @{}
    $plays = New-Object System.Collections.Generic.List[object]
    foreach ($n in @('client1', 'client2')) {
        $idLine = $logs[$n] | Select-String 'WALK client connected id=(\d+)' | Select-Object -First 1
        if (-not $idLine) { continue }
        $id = $idLine.Matches[0].Groups[1].Value
        foreach ($m in @($logs[$n] | Select-String '^WALK client lat_send seq=(\d+) unix=([\d.]+) age_ms=([\d.]+)')) {
            $g = $m.Matches[0].Groups
            $sends["${id}:$($g[1].Value)"] = @([double]$g[2].Value, [double]$g[3].Value)
        }
        $pattern = '^WALK client lat_play from=(\d+) seq=(\d+) recv=([\d.]+) push=([\d.]+) queue_ms=([\d.]+) playing=(\w+) out_ms=([\d.]+)'
        foreach ($m in @($logs[$n] | Select-String $pattern)) {
            $g = $m.Matches[0].Groups
            $plays.Add([pscustomobject]@{
                    Dir = "$($g[1].Value)>$id ($n listens)"; Key = "$($g[1].Value):$($g[2].Value)"
                    Recv = [double]$g[3].Value; Push = [double]$g[4].Value; Queue = [double]$g[5].Value
                    Playing = $g[6].Value -eq 'True'; Out = [double]$g[7].Value
                })
        }
    }
    foreach ($m in @($logs['host'] | Select-String '^WALK host lat_host from=(\d+) seq=(\d+) unix=([\d.]+)')) {
        $g = $m.Matches[0].Groups
        $hostSeen["$($g[1].Value):$($g[2].Value)"] = [double]$g[3].Value
    }
    Write-Host 'latency legs, median ms (timed frames only while the playback runs; one machine: one clock):'
    $timed = 0
    foreach ($group in @($plays | Where-Object { $_.Playing } | Group-Object Dir)) {
        $rows = @($group.Group)
        $hold = @($rows | ForEach-Object { ($_.Push - $_.Recv) * 1000 })
        $queue = @($rows | ForEach-Object { $_.Queue })
        $out = @($rows | ForEach-Object { $_.Out })
        $age = @(); $up = @(); $down = @(); $total = @()
        foreach ($r in $rows) {
            if (-not ($sends.ContainsKey($r.Key) -and $hostSeen.ContainsKey($r.Key))) { continue }
            $s = $sends[$r.Key]; $h = $hostSeen[$r.Key]
            $age += $s[1]; $up += ($h - $s[0]) * 1000; $down += ($r.Recv - $h) * 1000
            $total += $s[1] + ($r.Push - $s[0]) * 1000 + $r.Queue + $r.Out
        }
        $timed += $rows.Count
        $jitter = @($rows | ForEach-Object { ($_.Push - $_.Recv) * 1000 + $_.Queue })
        Write-Host ("  {0}: frames={1} full={2}" -f $group.Name, $rows.Count, $total.Count)
        Write-Host ("    age {0} | up {1} | down {2} | reorder {3} | queue {4} | output {5} | total {6} (p10 {7}, p90 {8})" -f `
            (Fmt (Get-Stat $age 0.5)), (Fmt (Get-Stat $up 0.5)), (Fmt (Get-Stat $down 0.5)), (Fmt (Get-Stat $hold 0.5)),
            (Fmt (Get-Stat $queue 0.5)), (Fmt (Get-Stat $out 0.5)), (Fmt (Get-Stat $total 0.5)),
            (Fmt (Get-Stat $total 0.1)), (Fmt (Get-Stat $total 0.9)))
        $jm = Get-Stat $jitter 0.5; $tm = Get-Stat $total 0.5
        $share = if ([double]::IsNaN($tm) -or $tm -le 0) { '-' } else { '{0:0}%' -f (100 * $jm / $tm) }
        Write-Host ("    jitter buffer (reorder + queue): median {0} ms (p90 {1}), {2} of the median total" -f `
            (Fmt $jm), (Fmt (Get-Stat $jitter 0.9)), $share)
    }
    $echoes = @($logs['client1'] | Select-String '^WALK client click_echo ms=([\d.]+)' |
        ForEach-Object { [double]$_.Matches[0].Groups[1].Value })
    $clicks = @($logs['client2'] | Select-String '^WALK client click n=\d+ unix=([\d.]+)' |
        ForEach-Object { [double]$_.Matches[0].Groups[1].Value })
    $onsets = @($logs['client1'] | Select-String '^WALK client click_onset ')
    # The onsets paired as clicks (not their echoes), on client 1's clock.
    $heard = @($logs['client1'] | Select-String '^WALK client click_echo .* click_unix=([\d.]+)' |
        ForEach-Object { [double]$_.Matches[0].Groups[1].Value })
    if ($clicks.Count -gt 0 -or $echoes.Count -gt 0) {
        Write-Host ("acoustic mouth to ear, ms: clicks played {0}, onsets heard {1}, echoes paired {2}" -f `
            $clicks.Count, $onsets.Count, $echoes.Count)
        Write-Host ("  median {0} | min {1} | p10 {2} | p90 {3} | max {4}" -f (Fmt (Get-Stat $echoes 0.5)),
            (Fmt (Get-Stat $echoes 0)), (Fmt (Get-Stat $echoes 0.1)), (Fmt (Get-Stat $echoes 0.9)), (Fmt (Get-Stat $echoes 1)))
        Write-Host ("  all: {0}" -f (($echoes | ForEach-Object { $_.ToString('0', [cultureinfo]::InvariantCulture) }) -join ' '))
        # Only on one machine, where both logs share a clock: from asking for a click to the microphone hearing it.
        $loops = @()
        foreach ($c in $clicks) {
            $first = @($heard | Where-Object { $_ -ge $c - 0.05 -and $_ -le $c + 0.6 }) | Select-Object -First 1
            if ($null -ne $first) { $loops += ($first - $c) * 1000 }
        }
        if ($loops.Count -gt 0) {
            Write-Host ("  click to microphone (output + air + input device buffers; one machine only): median {0} ms of {1}" -f `
                (Fmt (Get-Stat $loops 0.5)), $loops.Count)
        }
    }
    foreach ($n in @('host', 'client1', 'client2')) {
        $line = @($logs[$n] -match '^WALK \w+ voice (t=|quit)') | Select-Object -Last 1
        $cpu = @([regex]::Matches("$line", '(encode_us|decode_us|relay_us)=[\d.]+') | ForEach-Object { $_.Value })
        $rtt = @($logs[$n] -match '^WALK \w+ enet t=') | Select-Object -Last 1
        $rtts = @([regex]::Matches("$rtt", ' rtt=\d+') | ForEach-Object { $_.Value.Trim() })
        if ($cpu.Count -gt 0 -or $rtts.Count -gt 0) { Write-Host ("  {0}: {1} {2}" -f $n, ($cpu -join ' '), ($rtts -join ' ')) }
    }
    return @{ Clicks = $clicks.Count; Echoes = $echoes.Count; Timed = $timed }
}

if ($Analyze) {
    $null = Show-Latency $Logs
    exit 0
}

# Claude sessions get GODOT_BIN and GODOT_GUI_BIN from the env block of ~/.claude/settings.json; a human's own
# terminal usually does not, so fall back to that file.
$ClaudeSettings = Join-Path $env:USERPROFILE '.claude\settings.json'
function Get-GodotVar([string]$Name) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if (-not $value -and (Test-Path $ClaudeSettings)) {
        $settings = Get-Content $ClaudeSettings -Raw | ConvertFrom-Json
        if ($settings.env) { $value = $settings.env.$Name }
    }
    return $value
}
if (-not $Godot) { $Godot = if ($Headless) { Get-GodotVar 'GODOT_BIN' } else { Get-GodotVar 'GODOT_GUI_BIN' } }
if (-not $Godot) { $Godot = Get-GodotVar 'GODOT_BIN' }
if (-not $Godot -or -not (Test-Path $Godot)) {
    throw "Godot not found: pass -Godot <path to the Godot exe>, or set GODOT_BIN (and GODOT_GUI_BIN for windows) here or in the env block of $ClaudeSettings"
}
if ($KillClientAfter -gt 0 -and ($Seconds -le 0 -or $KillClientAfter -ge $Seconds)) {
    throw '-KillClientAfter needs -Seconds larger than it'
}
if ($Cheat -and $Seconds -le ($CheatSpeedAt + 3)) { throw "-Cheat needs -Seconds above $($CheatSpeedAt + 3)" }
if ($Shots -and $Headless) { throw '-Shots needs windows (no -Headless)' }
if ($Shots -and $Seconds -le $ShotAt) { throw "-Shots needs -Seconds above $ShotAt" }
$console = $Godot -replace '(?<!_console)\.exe$', '_console.exe'
if (-not (Test-Path $console)) { $console = $Godot }
# A checkout that just switched branches has an old list of class_name scripts in .godot\, and running a scene does
# not rescan it: every new class (SpikeVoiceClicks...) is then "not declared" (#16, the second machine). A headless
# import refreshes it; with nothing to import it takes a few seconds. stdout only, as below.
& $console --headless --path "$Root" --import | Out-Null
if ($LASTEXITCODE -ne 0) { throw "the Godot import failed (exit $LASTEXITCODE): run tools\run.cmd check for details" }
if ($ListMics) {
    # The console build prints to this terminal; a real audio driver, or the list is empty. Listing starts no microphone.
    # stdout only: with $ErrorActionPreference Stop, PowerShell 5.1 turns any stderr line of a native exe into an error.
    & $console --display-driver headless --rendering-driver dummy --audio-driver WASAPI --path "$Root" -s res://spike/voice/list_mics.gd |
        Where-Object { $_ -match '^MICS? ' }
    exit 0
}
if ($Bench) {
    # The CPU cost of one voice stream on this machine (#16); headless, starts no audio device.
    & $console --headless --path "$Root" -s res://spike/voice/codec_bench.gd | Where-Object { $_ -match '^BENCH ' }
    exit $LASTEXITCODE
}
if ($Lan -and $Join) { throw 'pass -Lan on the first machine and -Join on the second, not both' }
if (($Lan -or $Join) -and (($Seconds -gt 0 -and -not $Latency) -or $Headless -or $Cheat -or $KillClientAfter -gt 0)) {
    throw '-Lan and -Join start windows for people to play; no -Headless, -Cheat or -KillClientAfter, and -Seconds only with -Latency'
}
if ($Latency) {
    if ($Headless) { throw '-Latency needs a real audio driver: no -Headless' }
    $Voice = 'mic'
    if (-not $PSBoundParameters.ContainsKey('Cutoff')) { $Cutoff = 30 }
    if (Test-Path $MicWav) { Remove-Item $MicWav }
}
if ($Listen -lt 0) { $Listen = if ($Seconds -gt 0) { 0 } else { 1 } }
New-Item -ItemType Directory -Force $Logs | Out-Null

function Start-Peer([string]$Name, [int]$X, [string[]]$UserArgs) {
    $log = Join-Path $Logs "$Name.log"
    $png = Join-Path $Logs "$Name.png"
    if (Test-Path $log) { Remove-Item $log }
    if (Test-Path $png) { Remove-Item $png }
    $godotArgs = @('--path', "`"$Root`"", '--log-file', "`"$log`"")
    if ($Headless) { $godotArgs += '--headless' } else { $godotArgs += @('--resolution', '640x400', '--position', "$X,80") }
    $godotArgs += @($Scene, '--') + $UserArgs + @('--tick-hz', "$TickHz", '--interp-ticks', "$InterpTicks")
    $godotArgs += @('--sim-latency-ms', "$LatencyMs", '--sim-jitter-ms', "$JitterMs", '--sim-loss', "$Loss")
    # The host outlives the clients by 3 s, so each client's last snapshot is from a live host.
    $quitAfter = if ($Name -eq 'host') { $Seconds + 3 } else { $Seconds }
    if ($Seconds -gt 0) { $godotArgs += @('--quit-after-seconds', "$quitAfter") }
    if ($Shots) { $godotArgs += @('--screenshot-at', "$ShotAt", '--screenshot', "`"$png`"") }
    $style = if ($Headless) { 'Hidden' } else { 'Normal' }
    $p = Start-Process -FilePath $Godot -ArgumentList $godotArgs -PassThru -WindowStyle $style
    $null = $p.Handle  # keeps ExitCode readable after the process ends (PowerShell 5.1)
    Write-Host "started $Name (pid $($p.Id)), log $log"
    return [pscustomobject]@{ Name = $Name; Process = $p; Log = $log; Png = $png }
}

# What each client says and whether its output is muted (the Voice bus is measured either way).
function Voice-Args([int]$N) {
    if ($Latency) {
        # Client 1 captures and listens for clicks, silent itself; client 2 speaks nothing, clicks and plays client 1.
        if ($N -eq 2) { return @('--voice', 'off', '--click-every', "$ClickEvery", '--voice-cutoff', "$Cutoff", '--voice-gain-db', "$EchoGainDb") }
        $micArgs = @('--voice', 'mic', '--detect-clicks', '--mute-output', '--voice-cutoff', "$Cutoff", '--mic-dump', "`"$MicWav`"")
        if ($MicDevice) { $micArgs += @('--mic-device', "`"$MicDevice`"") }
        if ($NoDenoise) { $micArgs += '--no-denoise' }
        return $micArgs
    }
    # One machine has one microphone, so client 2 plays a tone; with -Join client 2 is alone on its machine.
    $source = if ($Voice -eq 'mic' -and ($N -eq 1 -or $Join)) { 'mic' } elseif ($Voice -eq 'off') { 'off' } else { 'tone' }
    $voiceArgs = @('--voice', $source, '--tone-hz', $(if ($N -eq 1) { '440' } else { '660' }), '--voice-cutoff', "$Cutoff")
    if ($source -eq 'mic' -and $MicDevice) { $voiceArgs += @('--mic-device', "`"$MicDevice`"") }
    if ($source -eq 'mic' -and $NoDenoise) { $voiceArgs += '--no-denoise' }
    if (-not $Lan -and -not $Join -and $Listen -ne $N) { $voiceArgs += '--mute-output' }
    return $voiceArgs
}
# On two machines each one starts only its own peers: the other peers' logs here would be stale, and -Analyze would
# read them as this run's.
$elsewhere = if ($Lan) { @('client2') } elseif ($Join) { @('host', 'client1') } else { @() }
foreach ($name in $elsewhere) {
    foreach ($ext in @('log', 'png')) {
        $stale = Join-Path $Logs "$name.$ext"
        if (Test-Path $stale) { Remove-Item $stale }
    }
}
$hostArgs = @('--host', '--port', "$Port", '--voice-cutoff', "$Cutoff")
# -Latency: the players stand still, so the relayed click's loudness stays the same.
$walk = if ($Latency) { @() } else { @('--auto') }
if ($Join) {
    $client2 = Start-Peer 'client2' 670 (@('--join', $Join, '--port', "$Port") + $walk + (Voice-Args 2))
    Write-Host "one client joining $Join`:$Port started; close its window to stop. Log as above."
    exit 0
}
if ($Lan) { $hostArgs += @('--bind', '0.0.0.0') }
$joinArgs = @('--join', '127.0.0.1', '--port', "$Port") + $walk
$cheatArgs = if ($Cheat) { @('--cheat-teleport-at', "$CheatTeleportAt", '--cheat-speed-at', "$CheatSpeedAt") } else { @() }
$hostPeer = Start-Peer 'host' 20 $hostArgs
Start-Sleep -Milliseconds 800
$client1 = Start-Peer 'client1' 670 ($joinArgs + (Voice-Args 1))
if ($Lan) {
    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.InterfaceAlias -notmatch '^vEthernet' } |
        ForEach-Object { $_.IPAddress })  # vEthernet: WSL and Hyper-V, unreachable from another machine
    Write-Host "host and client 1 started. On the second machine run, with one of: $($addresses -join ', ')"
    $second = if ($Latency) { "-Latency$(if ($Seconds -gt 0) { " -Seconds $([math]::Max(1, $Seconds - 10))" })" } else { "-Voice $Voice" }
    Write-Host "  powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1 -Join <address> $second -Port $Port"
    exit 0
}
$client2 = Start-Peer 'client2' 1320 ($joinArgs + $cheatArgs + (Voice-Args 2))
if ($Seconds -le 0) {
    Write-Host 'three windows started; close them to stop. Logs as above.'
    exit 0
}

$failures = New-Object System.Collections.Generic.List[string]
function Need([bool]$Ok, [string]$What) { if (-not $Ok) { $failures.Add($What) } }
# @() everywhere: a missing or one-line log must not turn a -match into a vacuous pass.
function Read-Log($Peer) { if (Test-Path $Peer.Log) { @(Get-Content $Peer.Log) } else { @() } }
function Has([string[]]$Log, [string]$Pattern) { @($Log -match $Pattern).Count -gt 0 }

$started = Get-Date
if ($KillClientAfter -gt 0) {
    Start-Sleep -Seconds $KillClientAfter
    Stop-Process -Id $client2.Process.Id -Force
    Write-Host "killed client2 (pid $($client2.Process.Id)) at $KillClientAfter s"
}
foreach ($peer in @($hostPeer, $client1, $client2)) {
    $left = [int]($Seconds + 20 - ((Get-Date) - $started).TotalSeconds)
    if (-not $peer.Process.WaitForExit([math]::Max($left, 1) * 1000)) {
        Stop-Process -Id $peer.Process.Id -Force
        $failures.Add("$($peer.Name) quit by itself")
    }
}

# Checks on the logs.
$hostLog = @(Read-Log $hostPeer)
$c1Log = @(Read-Log $client1)
$c2Log = @(Read-Log $client2)
function Id-Of([string[]]$Log) {
    $m = $Log | Select-String -Pattern 'WALK client connected id=(\d+)' | Select-Object -First 1
    if ($m) { return [int]$m.Matches[0].Groups[1].Value } else { return 0 }
}
$id1 = Id-Of $c1Log
$id2 = Id-Of $c2Log
Need ($id1 -gt 1) 'client1 connected and got a peer id'
Need ($id2 -gt 1) 'client2 connected and got a peer id'
Need (Has $hostLog "^WALK host listening on 127\.0\.0\.1:$Port$") 'host listening'
foreach ($id in @($id1, $id2)) {
    Need (Has $hostLog "^WALK host first_move id=$id ") "host accepted a move from $id"
}
foreach ($pair in @(@($client1, $c1Log, $id2), @($client2, $c2Log, $id1))) {
    $name = $pair[0].Name
    Need (Has $pair[1] '^WALK client placed epoch=1 ') "$name was placed by the host"
    Need (Has $pair[1] "^WALK client sees id=$($pair[2])$") "$name saw $($pair[2])"
    if (-not $Latency) { Need (Has $pair[1] "^WALK client sees_moving id=$($pair[2])$") "$name saw $($pair[2]) move" }
}
foreach ($peer in @($hostPeer, $client1, $client2)) {
    $log = @(Read-Log $peer)
    Need (-not (Has $log 'SCRIPT ERROR|^ERROR:')) "$($peer.Name) logged no errors"
    if ($peer -ne $hostPeer) { Need (-not (Has $log '^WALK client rejected')) "$($peer.Name) rejected no packets" }
    if ($Shots) { Need (Has $log '^WALK \w+ screenshot .* OK$') "$($peer.Name) saved a screenshot" }
}
Need (-not (Has $hostLog '^WALK host rejected malformed')) 'host got no malformed packets'
Need (-not (Has $hostLog "^WALK host rejected \w+ id=$id1 ")) "host never rejected the honest client $id1"
Need (-not (Has $c1Log '^WALK client corrected')) 'client1 was never corrected'
if ($Cheat) {
    Need (Has $c2Log '^WALK client cheat teleport') 'client2 teleported'
    Need (Has $hostLog "^WALK host rejected teleport id=$id2 ") "host rejected the teleport of $id2"
    Need (Has $hostLog "^WALK host rejected speed id=$id2 ") "host rejected the speed of $id2"
    Need (Has $c2Log '^WALK client corrected') 'client2 was corrected'
} else {
    Need (-not (Has $hostLog '^WALK host rejected')) 'host rejected nothing'
    Need (-not (Has $c2Log '^WALK client corrected')) 'client2 was never corrected'
}
$hostQuit = @($hostLog -match '^WALK host quit ') | Select-Object -Last 1
$c1Quit = @($c1Log -match '^WALK client quit ') | Select-Object -Last 1
$c2Quit = @($c2Log -match '^WALK client (quit|t=)') | Select-Object -Last 1
# Without simulated network trouble and with the default delay, interpolation must almost never
# run out of snapshots (a host hitch that shifts the clock for good would show up here).
function Starved-Share([string]$Line) {
    if ($Line -match 'interpolated=(\d+) starved=(\d+)') {
        return [int]$Matches[2] / [math]::Max(1, [int]$Matches[1] + [int]$Matches[2])
    }
    return 1.0
}
if ($LatencyMs -eq 0 -and $JitterMs -eq 0 -and $Loss -eq 0 -and $InterpTicks -ge 2) {
    foreach ($pair in @(@('host', $hostQuit), @('client1', $c1Quit))) {
        $share = Starved-Share $pair[1]
        Need ($share -lt 0.02) ("{0} interpolation starved under 2 % (was {1:P1})" -f $pair[0], $share)
    }
}
Need ($hostPeer.Process.ExitCode -eq 0 -and $hostQuit) "host ran to the end (exit $($hostPeer.Process.ExitCode))"
Need ($client1.Process.ExitCode -eq 0 -and $c1Quit) "client1 ran to the end (exit $($client1.Process.ExitCode))"
# Every client quits 3 s before the host, so the host must see each one leave and end empty.
Need (Has $hostLog "^WALK host peer_left id=$id1$") "host logged peer_left for $id1"
Need (Has $hostLog "^WALK host peer_left id=$id2$") "host logged peer_left for $id2"
Need ($hostQuit -match 'peers=\[\] ') "host ends with no peers: $hostQuit"
if ($KillClientAfter -gt 0) {
    # A real kill: no goodbye from client 2, so the host only learns of it from the ENet timeout.
    Need (-not (Has $c2Log '^WALK client quit ')) 'client2 was hard-killed (no quit line)'
    Need ($client2.Process.ExitCode -ne 0) "client2 exit code shows a kill (exit $($client2.Process.ExitCode))"
    Need (Has $c1Log "^WALK client lost id=$id2$") "client1 saw $id2 leave"
    $from = [array]::IndexOf($hostLog, "WALK host peer_left id=$id2")
    $to = [array]::IndexOf($hostLog, "WALK host peer_left id=$id1")
    $between = if ($from -ge 0 -and $to -gt $from) { @($hostLog[$from..$to]) } else { @() }
    Need (Has $between "^WALK host t=\S+ peers=\[$id1@\([^)]*\)\] ") "host went on with only $id1 after $id2 left"
    Need ($c1Quit -match 'status=connected .*players=\[\]$') "client1 ends connected with no remote players: $c1Quit"
} else {
    Need ($client2.Process.ExitCode -eq 0) "client2 ran to the end (exit $($client2.Process.ExitCode))"
}

if ($Latency) {
    Need (Has $hostLog "^WALK host voice_first $id1>$id2 ") "host relayed voice $id1>$id2"
    Need (Has $c2Log "^WALK client voice_first from=$id1$") "client2 played voice from $id1"
}
if ($Voice -ne 'off' -and -not $Latency) {
    $simulated = $LatencyMs -gt 0 -or $JitterMs -gt 0 -or $Loss -gt 0
    $hostVoice = @($hostLog -match '^WALK host voice quit ') | Select-Object -Last 1
    Need ([bool]$hostVoice) 'host logged its voice totals'
    foreach ($pair in @("$id1>$id2", "$id2>$id1")) {
        Need (Has $hostLog "^WALK host voice_first $pair ") "host relayed voice $pair"
    }
    if ($hostVoice -match 'max_delivered=(-?[\d.]+) ') {
        Need ([double]$Matches[1] -le $Cutoff + 0.001) "host delivered nothing beyond $Cutoff m (max $($Matches[1]))"
    }
    Need ($hostVoice -match ' flood=0 unplaced=0 ') "host dropped no honest voice frames: $hostVoice"
    # How far apart the clients got, as client 1 measured it.
    $levels = @{}
    foreach ($pair in @(@($client1, $c1Log, $id2), @($client2, $c2Log, $id1))) {
        $name = $pair[0].Name
        Need (Has $pair[1] "^WALK client voice_first from=$($pair[2])$") "$name played voice from $($pair[2])"
        $levels[$name] = @($pair[1] | Select-String "^WALK client level from=$($pair[2]) dist=([\d.]+) peak_db=(-?[\d.]+)" |
            ForEach-Object { [pscustomobject]@{ D = [double]$_.Matches[0].Groups[1].Value; Db = [double]$_.Matches[0].Groups[2].Value } })
        $quit = @($pair[1] -match '^WALK client voice quit ') | Select-Object -Last 1
        Need ([bool]$quit) "$name logged its voice totals"
        if (-not $simulated) {
            # The last voice line that still lists the speaker: it drops out when the other client quits first.
            $pattern = "from=\[.*$($pair[2]):\{recv=(\d+) late=\d+ fec=(\d+) lost=(\d+) "
            $line = @($pair[1] -match "^WALK client voice (t=|quit).*$($pair[2]):\{") | Select-Object -Last 1
            $counts = $line -match $pattern
            Need $counts "$name logged voice counts for $($pair[2]): $line"
            if ($counts) {
                $recv = [int]$Matches[1]; $gaps = [int]$Matches[2] + [int]$Matches[3]
                # Frames the host culled for a moment at the cutoff show up as gaps too.
                Need ($gaps -le [math]::Max(60, 0.1 * $recv)) "$name missed few voice frames ($gaps of $recv)"
            }
        }
    }
    $beyondSeen = $false
    foreach ($name in @('client1', 'client2')) {
        if ($name -eq 'client2' -and $Voice -eq 'mic') { continue }  # client 1's microphone level is anything
        $rows = @($levels[$name])
        $near = @($rows | Where-Object { $_.D -lt $Cutoff / 2 -and $_.Db -gt -150 } | ForEach-Object { $_.Db } | Sort-Object)
        $farRows = @($rows | Where-Object { $_.D -gt $Cutoff * 0.75 -and $_.D -lt $Cutoff })
        # Audible rows only: a far band gone silent (a cutoff that bites too early) must fail, not pass.
        $far = @($farRows | Where-Object { $_.Db -gt -150 } | ForEach-Object { $_.Db } | Sort-Object)
        Need ($near.Count -ge 3) "$name heard voice nearer than $($Cutoff / 2) m"
        if ($farRows.Count -ge 3) {
            # At least one: on coming back into range, voice resumes only after the network delay and the 60 ms
            # prebuffer (150-200 ms, up to 1.5 m of walking), so some windows near the cutoff are rightly silent.
            Need ($far.Count -ge 1) ("$name still heard voice between {0} and {1} m ({2} of {3} windows)" -f ($Cutoff * 0.75), $Cutoff, $far.Count, $farRows.Count)
        } else {
            Write-Host "note: $name spent under 3 level windows between $($Cutoff * 0.75) and $Cutoff m; falloff near the cutoff was not checked"
        }
        if ($near.Count -ge 3 -and $far.Count -ge 3) {
            $nearMedian = $near[[int]($near.Count / 2)]
            $farMedian = $far[[int]($far.Count / 2)]
            Need ($nearMedian -gt $farMedian + 3) "$name louder near than far (median $nearMedian dB vs $farMedian dB)"
        }
        # Silent beyond the cutoff: only a window with a whole window beyond it (+0.3 m) before it. After a crossing
        # the queued 60-120 ms still play at the last, near-zero gain (-46 dB was seen 2.7 m past the cutoff).
        for ($i = 2; $i -lt $rows.Count; $i++) {
            $beyond = $Cutoff + 0.3
            if ($rows[$i - 2].D -gt $beyond -and $rows[$i - 1].D -gt $beyond -and $rows[$i].D -gt $beyond) {
                $beyondSeen = $true
                Need ($rows[$i].Db -le -100) "$name silent beyond the cutoff (at $($rows[$i].D) m: $($rows[$i].Db) dB)"
            }
        }
    }
    if ($beyondSeen) {
        Need ($hostVoice -notmatch 'culled=\{\s*\}') "host culled voice beyond the cutoff: $hostVoice"
    } else {
        Write-Host "note: the clients never stayed beyond $Cutoff m, so silence beyond the cutoff was not checked (a smaller -Cutoff helps)"
    }
}

if ($Voice -ne 'off') {
    $lat = Show-Latency $Logs
    Need ($lat.Timed -ge 10) "listeners logged timed voice frames ($($lat.Timed))"
    if ($Latency) {
        Need ($lat.Clicks -ge 3) "client2 clicked ($($lat.Clicks))"
        Need ($lat.Echoes -ge 3) "client1's microphone heard clicks and their echoes ($($lat.Echoes) echoes; loudspeaker on and near the microphone? see $MicWav)"
    }
}
Write-Host "host:    $hostQuit"
Write-Host "client1: $c1Quit"
Write-Host "client2: $c2Quit"
if ($Shots) { Write-Host "screenshots: $($hostPeer.Png), $($client1.Png), $($client2.Png)" }
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'PASS'
exit 0
