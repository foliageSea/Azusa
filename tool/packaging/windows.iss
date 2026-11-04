#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef BuildNumber
  #error BuildNumber is required
#endif

[Setup]
AppId={{9746FD51-1A65-4935-9365-EC0584A4BFDA}
AppName=Azusa
AppVersion={#AppVersion}
AppVerName=Azusa {#AppVersion}
VersionInfoVersion={#AppVersion}.{#BuildNumber}
AppPublisher=foliageSea
AppPublisherURL=https://github.com/foliageSea/Azusa
DefaultDirName={autopf}\Azusa
DefaultGroupName=Azusa
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=Azusa-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\azusa.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Azusa"; Filename: "{app}\azusa.exe"
Name: "{autodesktop}\Azusa"; Filename: "{app}\azusa.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\azusa.exe"; Description: "{cm:LaunchProgram,Azusa}"; Flags: nowait postinstall skipifsilent
