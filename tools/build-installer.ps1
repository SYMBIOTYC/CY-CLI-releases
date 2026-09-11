# CY-CLI Windows installer build script (shared by build-windows.yml and validation workflows)
param(
    [Parameter(Mandatory = $true)][string]$BinPath,
    [Parameter(Mandatory = $true)][string]$WrapperPath,
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$OutDir = (Get-Location).Path,
    [string]$InstallerName = 'CY-CLI-x86_64-setup.exe',
    [string]$LauncherPath = '',
    [string]$BridgePath = '',
    [string]$AuthServerPath = '',
    [string]$ThemesDir = ''
)

$ErrorActionPreference = 'Stop'

$INSTALLER = Join-Path $OutDir $InstallerName
$BinDir    = Join-Path $OutDir 'bin'
$LicenseTxt = Join-Path $OutDir 'license.txt'
$IssPath   = Join-Path $OutDir 'installer.iss'

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Copy-Item $BinPath (Join-Path $BinDir 'cy.exe') -Force
Copy-Item $WrapperPath (Join-Path $OutDir 'cy-wrapper.ps1') -Force

# Optional parity assets (launcher + local bridge + branded themes).
if ($LauncherPath -and (Test-Path $LauncherPath)) { Copy-Item $LauncherPath (Join-Path $OutDir 'launch-cy.ps1') -Force }
if ($BridgePath -and (Test-Path $BridgePath)) { Copy-Item $BridgePath (Join-Path $OutDir 'cy_bridge.py') -Force }
if ($AuthServerPath -and (Test-Path $AuthServerPath)) { Copy-Item $AuthServerPath (Join-Path $OutDir 'cy_auth_server.py') -Force }
if ($ThemesDir -and (Test-Path $ThemesDir)) {
    $ThemesOut = Join-Path $OutDir 'themes'
    New-Item -ItemType Directory -Force -Path $ThemesOut | Out-Null
    Copy-Item (Join-Path $ThemesDir '*.tmTheme') $ThemesOut -Force -ErrorAction SilentlyContinue
}
$extraFiles = ''
if ($LauncherPath -and (Test-Path (Join-Path $OutDir 'launch-cy.ps1'))) { $extraFiles += "Source: ""launch-cy.ps1""; DestDir: ""{app}""; Flags: ignoreversion`r`n" }
if ($BridgePath -and (Test-Path (Join-Path $OutDir 'cy_bridge.py'))) { $extraFiles += "Source: ""cy_bridge.py""; DestDir: ""{app}""; Flags: ignoreversion`r`n" }
if ($AuthServerPath -and (Test-Path (Join-Path $OutDir 'cy_auth_server.py'))) { $extraFiles += "Source: ""cy_auth_server.py""; DestDir: ""{app}""; Flags: ignoreversion`r`n" }
if ($ThemesDir -and (Test-Path (Join-Path $OutDir 'themes\*.tmTheme'))) { $extraFiles += "Source: ""themes\*.tmTheme""; DestDir: ""{app}\themes""; Flags: ignoreversion`r`n" }

@"
CY-CLI is licensed under the Apache License 2.0.
See https://github.com/SYMBIOTYC/CY-CLI-releases/blob/main/LICENSE
"@ | Set-Content -Path $LicenseTxt -Encoding ASCII

$iss = @"
; CY-CLI Windows Installer
#define MyAppName "CY-CLI"
#define MyAppVersion "$Version"
#define MyAppPublisher "SYMBIOTYC"
#define MyAppURL "https://github.com/SYMBIOTYC/CY-CLI-releases"
#define MyAppExeName "launch-cy.ps1"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=license.txt
OutputDir=.
OutputBaseFilename=CY-CLI-x86_64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "addtopath"; Description: "Add {#MyAppName} to your PATH"; GroupDescription: "Additional options:"

[Files]
Source: "bin\cy.exe"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "cy-wrapper.ps1"; DestDir: "{app}"; Flags: ignoreversion
$extraFiles

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\launch-cy.ps1"""; Comment: "CY-CLI"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autostartup}\{#MyAppName}"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\launch-cy.ps1"""; Comment: "CY-CLI"
Name: "{commondesktop}\{#MyAppName}"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\launch-cy.ps1"""; Tasks: desktopicon; Comment: "CY-CLI"

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\launch-cy.ps1"" --version"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Flags: preservestringtype; Tasks: addtopath; Check: NeedsAddPath(ExpandConstant('{app}'))

[Code]
function NeedsAddPath(Path: string): Boolean;
var
  OldPath: string;
begin
  Result := False;
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', OldPath) then
    Exit;
  Result := Pos(UpperCase(Path), Uppercase(OldPath)) = 0;
end;
"@

Set-Content -Path $IssPath -Value $iss -Encoding ASCII

# Locate the Inno Setup compiler (preinstalled on windows-2022; choco as fallback)
$candidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles} 'Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup\ISCC.exe'),
    (Join-Path ${env:ProgramFiles} 'Inno Setup\ISCC.exe')
)
$iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    $shim = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($shim) { $iscc = $shim.Source }
}
if (-not $iscc) {
    choco install innosetup -y --no-progress | Out-Host
    $shim = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($shim) { $iscc = $shim.Source }
}
if (-not $iscc) {
    Write-Error 'Inno Setup compiler (ISCC.exe) was not found on this runner'
    exit 1
}

Write-Host "Using Inno Setup compiler: $iscc"
Push-Location $OutDir
try {
    & $iscc $IssPath
    if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

if (-not (Test-Path $INSTALLER)) { throw "Installer not created: $INSTALLER" }

Write-Host "Created $INSTALLER"
Get-ChildItem $INSTALLER | Select-Object FullName, Length
Get-FileHash -Algorithm SHA256 $INSTALLER | Select-Object -ExpandProperty Hash | Out-File -FilePath "$INSTALLER.sha256"
