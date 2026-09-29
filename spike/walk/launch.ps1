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
    [int]$Port = 24560
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Logs = Join-Path $Root 'tools\out\logs\walk-spike'
$Scene = 'res://spike/walk/walk_spike.tscn'
$CheatTeleportAt = 4
$CheatSpeedAt = 6

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
$Godot = if ($Headless) { Get-GodotVar 'GODOT_BIN' } else { Get-GodotVar 'GODOT_GUI_BIN' }
if (-not $Godot) { $Godot = Get-GodotVar 'GODOT_BIN' }
if (-not $Godot -or -not (Test-Path $Godot)) {
    throw "Godot not found: set GODOT_BIN (and GODOT_GUI_BIN for windows) here or in the env block of $ClaudeSettings"
}
if ($KillClientAfter -gt 0 -and ($Seconds -le 0 -or $KillClientAfter -ge $Seconds)) {
    throw '-KillClientAfter needs -Seconds larger than it'
}
if ($Cheat -and $Seconds -le ($CheatSpeedAt + 3)) { throw "-Cheat needs -Seconds above $($CheatSpeedAt + 3)" }
if ($Shots -and $Headless) { throw '-Shots needs windows (no -Headless)' }
if ($Shots -and $Seconds -le $ShotAt) { throw "-Shots needs -Seconds above $ShotAt" }
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

$joinArgs = @('--join', '127.0.0.1', '--port', "$Port", '--auto')
$cheatArgs = if ($Cheat) { @('--cheat-teleport-at', "$CheatTeleportAt", '--cheat-speed-at', "$CheatSpeedAt") } else { @() }
$hostPeer = Start-Peer 'host' 20 @('--host', '--port', "$Port")
Start-Sleep -Milliseconds 800
$client1 = Start-Peer 'client1' 670 $joinArgs
$client2 = Start-Peer 'client2' 1320 ($joinArgs + $cheatArgs)
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
    Need (Has $pair[1] "^WALK client sees_moving id=$($pair[2])$") "$name saw $($pair[2]) move"
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
