; Inno Setup script for Book Generator - Meta Hawladar Team
; Compiled by CI:
;   ISCC /DMyAppExeName=... /DMyAppVersion=... /DMyProfile=... /DMySourceDir=...
;        /DMyOutputDir=... /DMyOutputBaseFilename=... installer\windows.iss

#ifndef MyAppExeName
  #define MyAppExeName "BookGenerator.exe"
#endif
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef MyProfile
  #define MyProfile "template"
#endif
#ifndef MySourceDir
  #define MySourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef MyOutputDir
  #define MyOutputDir "..\build\installer"
#endif
#ifndef MyOutputBaseFilename
  #define MyOutputBaseFilename "BookGenerator-setup"
#endif

#define MyAppName "Book Generator"
#define MyAppPublisher "Meta Hawladar Team"
#define MyAppId "{{9C3F1A74-6B2E-4C58-9F0D-7A1E5C2D8B33}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyOutputBaseFilename}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayName={#MyAppName} {#MyAppVersion}
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
