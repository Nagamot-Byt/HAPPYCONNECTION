[Setup]
AppId={{C67D3A1B-3401-4A5A-981F-A1B2C3D4E5F6}
AppName=MedLink Connect
AppVersion=0.1.0
AppPublisher=MedLink Health Technology
DefaultDirName={autopf}\MedLink Connect
DefaultGroupName=MedLink Connect
OutputDir=..\..\build\windows\installer
OutputBaseFilename=MedLinkConnect-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\medlink_connect.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MedLink Connect"; Filename: "{app}\medlink_connect.exe"
Name: "{group}\MedLink Connect (Administrador)"; Filename: "{app}\medlink_connect_admin.bat"
Name: "{autodesktop}\MedLink Connect"; Filename: "{app}\medlink_connect.exe"; Tasks: desktopicon
Name: "{autodesktop}\MedLink Connect (Administrador)"; Filename: "{app}\medlink_connect_admin.bat"; Tasks: desktopicon

[Run]
Filename: "{app}\medlink_connect.exe"; Description: "Ejecutar MedLink Connect"; Flags: nowait postinstall skipifsilent
