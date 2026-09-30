@echo off
rem prime-game task runner for PowerShell and cmd: tools\run.cmd <command> [args]
rem Finds Python as PYTHON_BIN, else PYTHON_BIN from the env of the Claude settings (a human's own terminal lacks
rem it, #55: the project's .claude\settings.local.json, then %CLAUDE_CONFIG_DIR% or %USERPROFILE%\.claude
rem settings.json; PowerShell reads the JSON, without a script file, so no execution policy applies; the local
rem path goes in through the environment, so a quote in the checkout path cannot break the command), else the py
rem launcher, else python on PATH. run.py then fills the other machine paths from the same files.
rem No ( ) blocks around the call: inside a block %ERRORLEVEL% would be read before the call runs.
setlocal
set "PY="
set "PYFILE=%PYTHON_BIN%"
set "PYFROM=PYTHON_BIN"
if not defined PYFILE set "PYFROM=PYTHON_BIN in the env of the Claude settings"
set "PRIME_LOCAL_SETTINGS=%~dp0..\.claude\settings.local.json"
if not defined PYFILE for /f "usebackq delims=" %%P in (`powershell -NoProfile -NonInteractive -Command "$p=''; $d=$env:CLAUDE_CONFIG_DIR; if (-not $d) { $d=Join-Path $env:USERPROFILE '.claude' }; foreach ($f in @($env:PRIME_LOCAL_SETTINGS, (Join-Path $d 'settings.json'))) { if ($p) { break }; try { $v=(Get-Content -Raw -Encoding UTF8 -LiteralPath $f -ErrorAction Stop | ConvertFrom-Json).env.PYTHON_BIN; if ($v) { $p=$v } } catch {} }; $p" 2^>nul`) do set "PYFILE=%%P"
set "PRIME_LOCAL_SETTINGS="
if defined PYFILE if not exist "%PYFILE%" echo %PYFROM% points to a missing file: %PYFILE% 1>&2 && exit /b 1
if defined PYFILE set PY="%PYFILE%"
if not defined PY where py >nul 2>nul && set "PY=py -3"
if not defined PY set "PY=python"
%PY% "%~dp0run.py" %*
exit /b %ERRORLEVEL%
