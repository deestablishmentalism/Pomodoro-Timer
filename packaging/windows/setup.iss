; Pomodoro Timer - Inno Setup script (per-user install, no admin rights, no Python needed)
;
; Build the PyInstaller output first (dist\pomodoro-timer\), then:
;   iscc packaging\windows\setup.iss                       (version defaults below)
;   iscc /DMyAppVersion=1.2.3 packaging\windows\setup.iss  (override version)
; or simply run packaging\windows\build_windows.ps1
;
; Output: dist\PomodoroTimer-Setup-<version>.exe
; Relative paths are resolved from this script's folder.

#define MyAppName "Pomodoro Timer"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "Pomodoro Timer Team"
#define MyAppURL "https://github.com/deestablishmentalism/Pomodoro-Timer"
#define MyAppExeName "pomodoro-timer.exe"

[Setup]
; Keep this AppId constant across releases so upgrades replace the previous install
AppId={{E68A869C-4BD7-40DF-8D63-4BC2560F4D3C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\PomodoroTimer
DisableProgramGroupPage=yes
DisableDirPage=auto
OutputDir=..\..\dist
OutputBaseFilename=PomodoroTimer-Setup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\..\assets\timer-logo.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; Close a running copy before upgrading/uninstalling (files would otherwise be locked)
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Remove files from an older version (stale DLLs/modules) before copying the new build
Type: filesandordirs; Name: "{app}\_internal"

[Files]
Source: "..\..\dist\pomodoro-timer\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

