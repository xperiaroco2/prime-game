# Spike (#21): a host and two clients of kill_probe.tscn; client 2 is hard-killed (Stop-Process -Force, no goodbye
# packet) and the script reports whether the host and client 1 kept hearing each other. Run from the project root.
# One machine (all three peers here):
#   powershell -ExecutionPolicy Bypass -File spike\kill\kill_probe.ps1 -Impl spike -Modes W,W,W -Runs 3
# Two machines (#21 item 3): machine A runs host and client 1, machine B runs client 2 and kills it:
#   A: ... -Peers host,client1 -Bind * -Seconds 60
#   B: ... -Peers client2 -Address <A's LAN IPv4> -Seconds 60 -KillAt 10
# -Impl: spike (SceneMultiplayer over ENetMultiplayerPeer, as in #13), real (net/'s EnetTransport), raw (ENetConnection).
# -Timeouts short uses the #13 spike's 2-4 s ENet peer timeout for spike and raw; real always uses net/'s own.
# -Modes: host,client1,client2, each W (a window, GODOT_GUI_BIN) or H (headless, GODOT_BIN).
# -FreezeHost / -FreezeClient1 S:MS block that process's main thread for MS ms, S s after it starts (headless too).
# -Offscreen puts the windows at -30000,-30000 like `shot`; -Driver picks the rendering driver of the windows.
# A run PASSes when the local host and client 1 each saw no silence from the other over 1 s and no disconnect.
# Logs and one CSV row per run: tools\out\logs\kill-probe\ (a folder per run).
param(
    [ValidateSet('spike', 'real', 'raw')][string]$Impl = 'real',
    [string]$Modes = 'W,W,W',
    [ValidateSet('short', 'real')][string]$Timeouts = 'short',
    [string]$Peers = 'host,client1,client2',
    [string]$Address = '127.0.0.1',
    [string]$Bind = '127.0.0.1',
    [int]$Runs = 1,
    [int]$Seconds = 15,
    [int]$KillAt = 7,
    [int]$Port = 24580,
    [switch]$Offscreen,
    [switch]$NoKill,
    [string]$FreezeHost = '',
    [string]$FreezeClient1 = '',
    [ValidateSet('', 'd3d12', 'vulkan', 'opengl3')][string]$Driver = '',
    [string]$Out = ''
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Scene = 'res://spike/kill/kill_probe.tscn'
if (-not $Out) { $Out = Join-Path $Root 'tools\out\logs\kill-probe' }
$Csv = Join-Path $Out 'runs.csv'
New-Item -ItemType Directory -Force $Out | Out-Null
if (-not (Test-Path $Csv)) {
    'time,variant,run,verdict,host,client1,cpu_before,other_godot' | Out-File -Encoding ascii $Csv
}
$mode = $Modes.Split(',')
if ($mode.Count -ne 3) { throw '-Modes needs three letters: host,client1,client2' }
$local = $Peers.Split(',')
if ($KillAt -ge $Seconds) { throw '-KillAt must be less than -Seconds' }

function Start-Peer([string]$Name, [string]$M, [int]$X, [string]$Dir, [string[]]$UserArgs) {
    $log = Join-Path $Dir "$Name.log"
    $exe = if ($M -eq 'W') { $env:GODOT_GUI_BIN } else { $env:GODOT_BIN }
    if (-not $exe -or -not (Test-Path $exe)) { throw 'Set GODOT_BIN and GODOT_GUI_BIN; see tools\run.cmd doctor' }
    $a = @('--path', "`"$Root`"", '--log-file', "`"$log`"")
    if ($M -eq 'W') {
        $pos = if ($Offscreen) { '-30000,-30000' } else { "$X,80" }
        $a += @('--resolution', '480x300', '--position', $pos, '--audio-driver', 'Dummy')
        if ($Driver -eq 'opengl3') { $a += @('--rendering-method', 'gl_compatibility') }
        if ($Driver) { $a += @('--rendering-driver', $Driver) }
    } else { $a += '--headless' }
    $a += @($Scene, '--') + $UserArgs
    $style = if ($M -eq 'W') { 'Normal' } else { 'Hidden' }
    $p = Start-Process -FilePath $exe -ArgumentList $a -PassThru -WindowStyle $style
    $null = $p.Handle  # keeps ExitCode readable after the process ends (PowerShell 5.1)
    Write-Host "started $Name (pid $($p.Id)), log $log"
    return [pscustomobject]@{ Name = $Name; Process = $p; Log = $log }
}

function Verdict($Peer) {
    if (-not $Peer) { return '' }
    $line = @(Get-Content $Peer.Log -ErrorAction SilentlyContinue | Select-String -Pattern ' ev wall=\d+ verdict (\S+)') |
        Select-Object -Last 1
    if ($line) { $line.Matches[0].Groups[1].Value } else { 'NO_VERDICT' }
}

for ($run = 1; $run -le $Runs; $run++) {
    $variant = "$Impl-$($Modes -replace ',', '')" + $(if ($Driver) { "-$Driver" } else { '' }) +
        $(if ($Offscreen) { '-off' } else { '' }) + $(if ($NoKill) { '-nokill' } else { '' }) +
        $(if ($FreezeHost) { '-freezehost' } else { '' }) + $(if ($FreezeClient1) { '-freezec1' } else { '' }) +
        $(if ($local.Count -lt 3) { '-' + ($local -join '+') } else { '' })
    $dir = Join-Path $Out "$variant-$(Get-Date -Format 'HHmmss')-$run"
    New-Item -ItemType Directory -Force $dir | Out-Null
    # The load when the run starts: other agents' Godot processes may be running tests on this machine.
    $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
    $other = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Godot*' }).Count
    $common = @("--impl=$Impl", "--timeouts=$Timeouts", "--port=$Port", "--seconds=$Seconds", "--pid-dir=$dir")
    $h = $null; $c1 = $null; $c2 = $null
    if ($local -contains 'host') {
        $h = Start-Peer 'host' $mode[0] 20 $dir (@('--role=host', "--bind=$Bind") + $common + $(if ($FreezeHost) { "--freeze=$FreezeHost" } else { @() }))
        Start-Sleep -Milliseconds 800
    }
    if ($local -contains 'client1') {
        $c1 = Start-Peer 'client1' $mode[1] 520 $dir (@('--role=client', '--name=client1', "--address=$Address") + $common + $(if ($FreezeClient1) { "--freeze=$FreezeClient1" } else { @() }))
    }
    if ($local -contains 'client2') {
        $c2 = Start-Peer 'client2' $mode[2] 1020 $dir (@('--role=client', '--name=client2', "--address=$Address") + $common)
    }
    $started = Get-Date
    if ($c2 -and -not $NoKill) {
        Start-Sleep -Seconds $KillAt
        Stop-Process -Id $c2.Process.Id -Force
        $msg = "killed client2 pid $($c2.Process.Id) at $(Get-Date -Format 'HH:mm:ss.fff')"
        "$msg wall_ms=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())" | Out-File -Encoding ascii (Join-Path $dir 'kill.txt')
        Write-Host $msg
    }
    foreach ($peer in @($h, $c1, $c2)) {
        if (-not $peer) { continue }
        $left = [int]($Seconds + 25 - ((Get-Date) - $started).TotalSeconds)
        if (-not $peer.Process.WaitForExit([math]::Max($left, 1) * 1000)) { Stop-Process -Id $peer.Process.Id -Force }
    }
    $hv = Verdict $h
    $c1v = Verdict $c1
    $v = if (@($hv, $c1v) | Where-Object { $_ -and $_ -ne 'PASS' }) { 'FAIL' } elseif ($h -or $c1) { 'PASS' } else { 'n/a' }
    "$(Get-Date -Format 'HH:mm:ss'),$variant,$run,$v,$hv,$c1v,$cpu,$other" | Out-File -Append -Encoding ascii $Csv
    Write-Host "$variant run $run : $v  host=$hv client1=$c1v  (cpu $cpu%, other Godot processes $other) $dir"
    $Port += 2
}
