# Spike (#13): one command starts an ENet host and two clients on this machine (127.0.0.1), each with its own log in
# tools\out\logs\net-spike\. Run from the project root:
#   powershell -ExecutionPolicy Bypass -File spike\net\launch.ps1                   # three windows; close them by hand
#   powershell -ExecutionPolicy Bypass -File spike\net\launch.ps1 -Seconds 15 -KillClientAfter 7
#   powershell -ExecutionPolicy Bypass -File spike\net\launch.ps1 -Headless -Seconds 15 -KillClientAfter 7
# With -Seconds every process quits by itself and the script checks the logs: both clients connect, the host gets
# intents from both, each client sees both clients' positions, nobody logs a script error or a rejected packet.
# -KillClientAfter N hard-kills client 2 after N seconds (Stop-Process, no goodbye packet); then the host must log
# peer_left, and the host and client 1 must run to the end, exit with code 0 and end with only client 1 in the game.
# Exit code 0 means PASS. The windows use WASD in addition to the clients' --auto circle walk.
param(
    [switch]$Headless,
    [int]$Seconds = 0,
    [int]$KillClientAfter = 0,
    [int]$Port = 24560
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Logs = Join-Path $Root 'tools\out\logs\net-spike'
$Scene = 'res://spike/net/net_spike.tscn'

$Godot = if ($Headless) { $env:GODOT_BIN } else { $env:GODOT_GUI_BIN }
if (-not $Godot) { $Godot = $env:GODOT_BIN }
if (-not $Godot -or -not (Test-Path $Godot)) { throw 'Set GODOT_BIN (and GODOT_GUI_BIN for windows); see tools\run.cmd doctor' }
if ($KillClientAfter -gt 0 -and ($Seconds -le 0 -or $KillClientAfter -ge $Seconds)) {
    throw '-KillClientAfter needs -Seconds larger than it'
}
New-Item -ItemType Directory -Force $Logs | Out-Null

function Start-Peer([string]$Name, [int]$X, [string[]]$UserArgs) {
    $log = Join-Path $Logs "$Name.log"
    if (Test-Path $log) { Remove-Item $log }
    $godotArgs = @('--path', "`"$Root`"", '--log-file', "`"$log`"")
    if ($Headless) { $godotArgs += '--headless' } else { $godotArgs += @('--resolution', '640x400', '--position', "$X,80") }
    $godotArgs += @($Scene, '--') + $UserArgs
    # The host outlives the clients by 3 s, so each client's last snapshot is from a live host.
    $quitAfter = if ($Name -eq 'host') { $Seconds + 3 } else { $Seconds }
    if ($Seconds -gt 0) { $godotArgs += @('--quit-after-seconds', "$quitAfter") }
    $style = if ($Headless) { 'Hidden' } else { 'Normal' }
    $p = Start-Process -FilePath $Godot -ArgumentList $godotArgs -PassThru -WindowStyle $style
    $null = $p.Handle  # keeps ExitCode readable after the process ends (PowerShell 5.1)
    Write-Host "started $Name (pid $($p.Id)), log $log"
    return [pscustomobject]@{ Name = $Name; Process = $p; Log = $log }
}

$hostPeer = Start-Peer 'host' 20 @('--host', '--port', "$Port")
Start-Sleep -Milliseconds 800
$client1 = Start-Peer 'client1' 670 @('--join', '127.0.0.1', '--port', "$Port", '--auto')
$client2 = Start-Peer 'client2' 1320 @('--join', '127.0.0.1', '--port', "$Port", '--auto')
if ($Seconds -le 0) {
    Write-Host 'three windows started; close them to stop. Logs as above.'
    exit 0
}

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
        Write-Host "FAIL $($peer.Name) did not quit by itself"
    }
}

# Checks on the logs.
$failures = New-Object System.Collections.Generic.List[string]
function Need([bool]$Ok, [string]$What) { if (-not $Ok) { $failures.Add($What) } }
function Read-Log($Peer) { if (Test-Path $Peer.Log) { Get-Content $Peer.Log } else { @() } }
$hostLog = Read-Log $hostPeer
$c1Log = Read-Log $client1
$c2Log = Read-Log $client2
function Id-Of([string[]]$Log) {
    $m = $Log | Select-String -Pattern 'NET client connected id=(\d+)' | Select-Object -First 1
    if ($m) { return [int]$m.Matches[0].Groups[1].Value } else { return 0 }
}
$id1 = Id-Of $c1Log
$id2 = Id-Of $c2Log
Need ($id1 -gt 1) 'client1 connected and got a peer id'
Need ($id2 -gt 1) 'client2 connected and got a peer id'
Need ($hostLog -match "^NET host listening on 127\.0\.0\.1:$Port$").Count 'host listening'
foreach ($id in @($id1, $id2)) {
    Need ($hostLog -match "^NET host first_intent id=$id ").Count "host got a move intent from $id"
    Need ($c1Log -match "^NET client sees id=$id$").Count "client1 saw the position of $id"
}
Need ($c2Log -match "^NET client sees id=$id1$").Count "client2 saw the position of $id1"
foreach ($peer in @($hostPeer, $client1, $client2)) {
    $log = Read-Log $peer
    Need (-not ($log -match 'SCRIPT ERROR|^ERROR:')) "$($peer.Name) logged no errors"
    Need (-not ($log -match '^NET \w+ rejected')) "$($peer.Name) rejected no packets"
}
$hostQuit = $hostLog -match '^NET host quit ' | Select-Object -Last 1
$c1Quit = $c1Log -match '^NET client quit ' | Select-Object -Last 1
Need ($hostPeer.Process.ExitCode -eq 0 -and $hostQuit) "host ran to the end (exit $($hostPeer.Process.ExitCode))"
Need ($client1.Process.ExitCode -eq 0 -and $c1Quit) "client1 ran to the end (exit $($client1.Process.ExitCode))"
if ($KillClientAfter -gt 0) {
    Need ($hostLog -match "^NET host peer_left id=$id2$").Count "host logged peer_left for the killed client $id2"
    Need ($c1Log -match "^NET client lost id=$id2$").Count "client1 saw $id2 leave"
    Need ($hostLog -match "^NET host t=\S+ peers=\[$id1@\(\d+,\d+\)\] ").Count "host went on with only $id1"
    Need ($c1Quit -match "status=connected .*players=\[$id1@\(\d+,\d+\)\]$") "client1 ends connected with only ${id1}: $c1Quit"
} else {
    Need ($client2.Process.ExitCode -eq 0) "client2 ran to the end (exit $($client2.Process.ExitCode))"
}

Write-Host "host:    $hostQuit"
Write-Host "client1: $c1Quit"
Write-Host "client2: $($c2Log -match '^NET client (quit|t=)' | Select-Object -Last 1)"
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'PASS'
exit 0
