# CY-CLI Windows launcher (parity with packaging/macos/launcher).
#
#   1. Resolves a CY API key (ENV, %USERPROFILE%\.cy\auth.json — cyclic field
#      search CY_API_KEY|openai_api_key|OPENAI_API_KEY|api_key|API_KEY) and
#      writes it to auth.json so the `cy` CLI can authenticate.
#   2. Starts the local responses->chat bridge (pythonw/python, port 8790) if
#      it is not already running. The bridge also serves GET /v1/models and
#      HEAD for reachability checks.
#   3. Writes %USERPROFILE%\.cy\config.toml with base_url=http://127.0.0.1:8790/v1.
#   4. Opens a terminal (wt.exe, else cmd /k) running a wrapper .cmd that shows
#      the big pink CY splash, then runs `cy` in a real TTY with CY_API_KEY set.

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CyHome = if ($env:CY_HOME) { $env:CY_HOME } else { Join-Path $env:USERPROFILE '.cy' }
$Port = if ($env:CY_BRIDGE_PORT) { $env:CY_BRIDGE_PORT } else { '8790' }
New-Item -ItemType Directory -Force -Path $CyHome | Out-Null

$AuthFile = Join-Path $CyHome 'auth.json'
$Config = Join-Path $CyHome 'config.toml'

$KeyFields = @('CY_API_KEY', 'openai_api_key', 'OPENAI_API_KEY', 'api_key', 'API_KEY')

# --- Resolve the cy binary ---------------------------------------------------
function Find-CyBin {
    $candidates = @(
        (Join-Path $ScriptDir 'cy.exe'),
        (Join-Path $ScriptDir 'bin\cy.exe'),
        (Join-Path $env:USERPROFILE '.local\share\cy\bin\cy.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    foreach ($name in @('cy.exe', 'cy')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

# --- Resolve the bridge script ------------------------------------------------
function Find-Bridge {
    $candidates = @(
        (Join-Path $ScriptDir 'cy_bridge.py'),
        (Join-Path $ScriptDir '..\packaging\bridge\cy_bridge.py'),
        (Join-Path $ScriptDir '..\packaging\macos\cy_bridge.py')
    )
    foreach ($b in $candidates) {
        if (Test-Path $b) { return (Resolve-Path $b).Path }
    }
    return $null
}

function Test-CyPort {
    param([int]$P)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect('127.0.0.1', $P)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

$CyBin = Find-CyBin
if (-not $CyBin) {
    Write-Host 'CY: cy.exe not found. Run the install script first.' -ForegroundColor Red
    exit 1
}
$Bridge = Find-Bridge

# --- Resolve the API key (ENV first, cyclic field order) ------------------------
$Key = ''
foreach ($name in $KeyFields) {
    $v = [Environment]::GetEnvironmentVariable($name)
    if ($v -and $v.Trim()) { $Key = $v.Trim(); break }
}
if (-not $Key -and (Test-Path $AuthFile)) {
    try {
        $data = Get-Content $AuthFile -Raw | ConvertFrom-Json
        foreach ($name in $KeyFields) {
            $v = $data.$name
            if ($v -is [string] -and $v.Trim()) { $Key = $v.Trim(); break }
        }
    } catch { }
}

if (-not $Key) {
    # No key anywhere: open the CY authorization page in the browser and surface
    # a branded, readable message (CY Engine v2 phrase).
    Start-Process 'https://auth.symbiotyc.workers.dev' -ErrorAction SilentlyContinue
    $esc = [string][char]27
    Write-Host ''
    Write-Host "  ${esc}[1;35m██████╗██╗   ██╗${esc}[0m"
    Write-Host " ${esc}[1;35m██╔════╝╚██╗ ██╔╝${esc}[0m"
    Write-Host " ${esc}[1;35m██║      ╚████╔╝ ${esc}[0m"
    Write-Host " ${esc}[1;35m██║       ╚██╔╝  ${esc}[0m"
    Write-Host " ${esc}[1;35m╚██████╗   ██║   ${esc}[0m"
    Write-Host "  ${esc}[1;35m╚═════╝   ╚═╝${esc}[0m"
    Write-Host ''
    Write-Host '  Тебе нужен API ключ.'
    Write-Host '  Открыли страницу авторизации в браузере: https://auth.symbiotyc.workers.dev'
    Write-Host '  1. Войди через Google — получишь ключ вида cfat_...'
    Write-Host '  2. Сохрани его:  cy login --with-api-key'
    Write-Host '     или:  setx CY_API_KEY cfat_...'
    Write-Host '  3. Запусти CY заново.'
    Write-Host ''
    exit 1
}

# --- Write auth.json (overwrite empty one) ----------------------------------------
[pscustomobject]@{
    auth_mode      = 'apiKey'
    openai_api_key = $Key
} | ConvertTo-Json | Set-Content -Path $AuthFile -Encoding ASCII

# --- Start the local bridge if it is not already running --------------------------
if (-not (Test-CyPort ([int]$Port))) {
    if (-not $Bridge) {
        Write-Host 'CY: cy_bridge.py not found; continuing without local bridge.' -ForegroundColor Yellow
    } else {
        $Python = $null
        foreach ($p in @('pythonw.exe', 'python3.exe', 'python.exe')) {
            $cmd = Get-Command $p -ErrorAction SilentlyContinue
            if ($cmd) { $Python = $cmd.Source; break }
        }
        if (-not $Python) {
            $cmd = Get-Command 'py.exe' -ErrorAction SilentlyContinue
            if ($cmd) { $Python = $cmd.Source }
        }
        if (-not $Python) {
            Write-Host 'CY: python not found. Install Python 3 and try again.' -ForegroundColor Red
            exit 1
        }
        if (-not $env:CY_API_BASE_URL) { $env:CY_API_BASE_URL = 'https://cy.symbiotyc.workers.dev/v1' }
        $env:CY_BRIDGE_PORT = "$Port"
        $env:CY_HOME = $CyHome
        $env:CY_API_KEY = $Key
        $bridgeArgs = "`"$Bridge`""
        if ((Split-Path -Leaf $Python) -eq 'py.exe') { $bridgeArgs = "-3 `"$Bridge`"" }
        Start-Process -FilePath $Python -ArgumentList $bridgeArgs -WindowStyle Hidden
        for ($i = 0; $i -lt 50; $i++) {
            if (Test-CyPort ([int]$Port)) { break }
            Start-Sleep -Milliseconds 100
        }
    }
}

# --- Seed SYMBIOTYC-branded syntax themes on first launch --------------------------
$ThemesSrc = Join-Path $ScriptDir 'themes'
if (Test-Path $ThemesSrc) {
    $ThemesDst = Join-Path $CyHome 'themes'
    New-Item -ItemType Directory -Force -Path $ThemesDst | Out-Null
    Get-ChildItem -Path (Join-Path $ThemesSrc '*.tmTheme') -ErrorAction SilentlyContinue | ForEach-Object {
        $dst = Join-Path $ThemesDst $_.Name
        if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
    }
}

# --- Config (always written to ensure correct port) ---------------------------------
@"
# CY Config - generated by CY-CLI launcher
model = "cy/i1a"
model_provider = "symbiotyc"
model_context_window = 128000
model_auto_compact_token_limit = 96000
model_reasoning_summary = "auto"
model_reasoning_effort = "none"
approval_policy = "never"

[model_providers.symbiotyc]
name = "SYMBIOTYC"
base_url = "http://127.0.0.1:$Port/v1"
wire_api = "responses"
supports_websockets = false
models = ["cy/i1a"]
"@ | Set-Content -Path $Config -Encoding ASCII

# --- Build the first-screen splash (big pink CY ASCII art) ----------------------------
#   1;35 = bold magenta (pink), 0 = reset, 1;36 = bold cyan, 2;37 = dim grey.
$esc = [string][char]27
$PINK = "${esc}[1;35m"
$CYAN = "${esc}[1;36m"
$DIM = "${esc}[2;37m"
$RESET = "${esc}[0m"

$SplashFile = Join-Path $CyHome '.splash.ansi'
$splash = @"
${PINK}
  ██████╗██╗   ██╗
 ██╔════╝╚██╗ ██╔╝
 ██║      ╚████╔╝
 ██║       ╚██╔╝
 ╚██████╗   ██║
  ╚═════╝   ╚═╝${RESET}

 ${PINK}CY${RESET} ${DIM}— Symbiotic Coding Assistant${RESET}
 ${DIM}Loading TUI...${RESET}
"@
[IO.File]::WriteAllText($SplashFile, $splash)

# --- Wrapper .cmd executed inside the terminal window ----------------------------------
$CmdFile = Join-Path $CyHome '.cy_launch.cmd'
$cmdBody = @"
@echo off
set "CX_HOME=$CyHome"
set "CODEX_HOME=$CyHome"
set "CY_API_KEY=$Key"
chcp 65001 >nul
cls
type "$SplashFile"
cd /d "$env:USERPROFILE"
"$CyBin"
del "$SplashFile" >nul 2>&1
del "$CmdFile" >nul 2>&1
"@
[IO.File]::WriteAllText($CmdFile, $cmdBody)

# --- Open the terminal with the splash, then the CLI --------------------------------------
$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
if ($wt) {
    Start-Process wt.exe -ArgumentList "cmd.exe /k `"$CmdFile`""
} else {
    Start-Process cmd.exe -ArgumentList "/k `"$CmdFile`""
}
