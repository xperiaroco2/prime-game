# Spike (#12): download TwoVoIP v6.5, check its SHA-256 and install only the Windows x86_64 parts into
# addons/twovoip/ (git-ignored on this branch). v6.5, not v6.6: the v6.6 DLL crashes the Godot editor on x86_64
# (https://github.com/goatchurchprime/two-voip-godot-4/issues/107). Run from the project root:
#   powershell -ExecutionPolicy Bypass -File spike\voice\fetch-twovoip.ps1
$ErrorActionPreference = 'Stop'
$Url = 'https://github.com/goatchurchprime/two-voip-godot-4/releases/download/v6.5/TwoVoIP.zip'
$Sha = '811ac96d4b75314f90855e3136f9939f7a4bc4a01e51850640cff967afc20fc7'
$Zip = Join-Path $env:TEMP 'TwoVoIP-v6.5.zip'
$Tmp = Join-Path $env:TEMP 'TwoVoIP-v6.5'

if (-not (Test-Path $Zip) -or (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLower() -ne $Sha) {
    Write-Host "downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Zip -UseBasicParsing
}
$Got = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLower()
if ($Got -ne $Sha) { throw "SHA-256 mismatch: $Got" }

if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp }
Expand-Archive -Path $Zip -DestinationPath $Tmp
$Src = Join-Path $Tmp 'project\addons\twovoip'
$Dst = 'addons\twovoip'
if (Test-Path $Dst) { Remove-Item -Recurse -Force $Dst }
New-Item -ItemType Directory -Force (Join-Path $Dst 'libs') | Out-Null
Copy-Item (Join-Path $Src 'twovoip.gdextension'), (Join-Path $Src 'twovoip.gdextension.uid') $Dst
Copy-Item (Join-Path $Src 'libs\*windows*') (Join-Path $Dst 'libs')
Write-Host "installed TwoVoIP v6.5 (Windows x86_64) into $Dst"
