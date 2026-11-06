; ============================================================
;  PC Assistant — Windows Setup (Inno Setup 6)
;  GitHub Actions-e Flutter Windows build er por ei script
;  diye purno installer (Setup.exe) toiri hoy.
;  Version bodlate chaile nicher AppVersion line ta bodlao
;  (pubspec.yaml er version er sathe miliye rekho).
; ============================================================

#define AppName "Maliha AI"
#define AppVersion "1.0.0"
#define AppPublisher "Maliha AI"
#define AppExeName "pc_assistant.exe"

[Setup]
AppId={{7B2E4C10-9A3D-4F21-B6E8-1C5D9A2F3047}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=PCAssistant-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Desktop shortcut তৈরি করো"; GroupDescription: "Additional icons:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "PC Assistant চালাও"; Flags: nowait postinstall skipifsilent
