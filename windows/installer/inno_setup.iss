[Setup]
AppName=MedLink Connect
AppVersion=0.1.0
DefaultDirName={autopf}\MedLink Connect
DefaultGroupName=MedLink Connect
OutputDir=..\..\build\windows\installer
OutputBaseFilename=MedLinkConnect-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MedLink Connect"; Filename: "{app}\medlink_connect.exe"
Name: "{autodesktop}\MedLink Connect"; Filename: "{app}\medlink_connect.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Run]
Filename: "{app}\medlink_connect.exe"; Description: "Ejecutar MedLink Connect"; Flags: nowait postinstall skipifsilent
