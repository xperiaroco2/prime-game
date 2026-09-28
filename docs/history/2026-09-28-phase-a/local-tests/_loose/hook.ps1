$p = ([Console]::In.ReadToEnd() | ConvertFrom-Json).tool_input.file_path
if ($p -notlike '*.gd') { exit 0 }
& "$env:GDTOOLKIT_DIR\gdformat.exe" $p 2>&1 | Out-Null
$lint = & "$env:GDTOOLKIT_DIR\gdlint.exe" $p 2>&1
if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine(($lint | Out-String)); exit 2 }
