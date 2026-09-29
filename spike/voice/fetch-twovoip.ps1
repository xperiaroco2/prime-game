# Spike (#12): download TwoVoIP v6.6, check its SHA-256 and install only the Windows x86_64 parts into
# addons/twovoip/ (git-ignored on this branch). Run from the project root:
#   powershell -ExecutionPolicy Bypass -File spike\voice\fetch-twovoip.ps1
$ErrorActionPreference = 'Stop'
$Url = 'https://github.com/goatchurchprime/two-voip-godot-4/releases/download/v6.6/TwoVoIP.zip'
$Sha = 'e5a84a6e6bb14d6f734edf53d06bfb76e7835a31c0851d51de2421b2a91f8ad0'
$Zip = Join-Path $env:TEMP 'TwoVoIP-v6.6.zip'
$Tmp = Join-Path $env:TEMP 'TwoVoIP-v6.6'

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
New-Item -ItemType Directory -Force (Join-Path $Dst 'libs') | Out-Null
Copy-Item (Join-Path $Src 'twovoip.gdextension'), (Join-Path $Src 'twovoip.gdextension.uid') $Dst
Copy-Item (Join-Path $Src 'libs\*windows*') (Join-Path $Dst 'libs')
Write-Host "installed TwoVoIP v6.6 (Windows x86_64) into $Dst"
