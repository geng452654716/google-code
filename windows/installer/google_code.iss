#ifndef AppVersion
  #error AppVersion must be provided by tool/package_windows_exe.ps1.
#endif
#ifndef BuildNumber
  #error BuildNumber must be provided by tool/package_windows_exe.ps1.
#endif
#ifndef SourceDir
  #error SourceDir must be provided by tool/package_windows_exe.ps1.
#endif
#ifndef OutputDir
  #error OutputDir must be provided by tool/package_windows_exe.ps1.
#endif
#ifndef OutputBaseFilename
  #error OutputBaseFilename must be provided by tool/package_windows_exe.ps1.
#endif

#define AppName "Google Code"
#define AppPublisher "gengyujian"
#define AppExeName "google_code.exe"

[Setup]
AppId={{E1E60748-49D8-4E41-99A1-B4E1CC024D15}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion} (build {#BuildNumber})
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\Google Code
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#AppExeName}
VersionInfoVersion={#AppVersion}.{#BuildNumber}
VersionInfoDescription=Google Code personal desktop installer
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}

[Languages]
; Default.isl is bundled with every Inno Setup installation. Optional language
; packs are intentionally not required so a clean CI runner can compile the EXE.
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Only remove installer-owned empty directories. Vault, Credential Manager entries,
; and .gcbak backups live outside {app} and are intentionally preserved.
Type: dirifempty; Name: "{app}"
