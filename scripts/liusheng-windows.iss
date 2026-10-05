; 流声 Windows Installer - Inno Setup 7
#define AppName "流声"
#define AppExeName "Liusheng.exe"
#define AppVersion "2.2.3"
#define AppPublisher "流声"
#define AppURL "https://github.com/MomentarySS/Liusheng"
#define AppDescription "电台与播客，一处收听"
#define SourceDir "..\build\windows\x64\runner\Release"
#define OutputDir "..\dist"
#define OutputBaseFilename "liusheng-windows-2.2.3"

[Setup]
; Basic Application Information
AppId={{D789141F-15E6-4D24-B4FC-4A74BB179C96}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
; Output installer file
OutputBaseFilename={#OutputBaseFilename}
OutputDir={#OutputDir}
; Compression
Compression=lzma2
SolidCompression=yes
; UI Settings
WizardStyle=modern
SetupIconFile=..\windows\runner\resources\app_icon.ico
; Uninstall settings
UninstallDisplayIcon={app}\Liusheng.exe
UninstallDisplayName={#AppName}
; Version information
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppDescription}
VersionInfoCopyright=Copyright (C) 2024 流声 contributors
; Privileges
PrivilegesRequired=none
; Architecture
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Other settings
DisableProgramGroupPage=no
DisableReadyMemo=no
DisableDirPage=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startmenu"; Description: "创建开始菜单快捷方式"; GroupDescription: "快捷方式:"
Name: "quicklaunch"; Description: "创建快速启动栏快捷方式"; GroupDescription: "快捷方式:"

[Files]
; Main executable and DLLs
Source: "{#SourceDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
; Data directory (local storage, caches, etc.)
Source: "{#SourceDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start Menu Program Folder
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Comment: "{#AppDescription}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
; Desktop Icon
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Comment: "{#AppDescription}"; Tasks: desktopicon
; Start Menu Icon (always created if startmenu task is checked)
Name: "{userstartmenu}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Comment: "{#AppDescription}"; Tasks: startmenu

[Run]
; Launch application after installation
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// Initialize and register the application uninstall entry
function InitializeUninstall(): Boolean;
begin
  Result := True;
end;
