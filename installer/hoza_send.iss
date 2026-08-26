; HozaSend - Windows installer
;
; Produces one self-contained Setup.exe from the Flutter release build. Compile
; with Inno Setup 6:
;
;   installer\build_installer.ps1
;
; Everything the app needs - the exe, flutter_windows.dll, every plugin DLL and
; the whole data folder - is packed inside the single setup file, so there is
; nothing else for the user to download or unzip.

#define AppName        "HozaSend"
#define AppVersion     "1.0.0"
#define AppPublisher   "Rahoz Osman Salim"
#define AppExeName     "hoza_send.exe"
#define AppContact     "hozahoza2001@gmail.com"

; Where `flutter build windows --release` leaves its output.
#define BuildDir       "..\build\windows\x64\runner\Release"

; Must agree with AppConstants in lib/core/constants/app_constants.dart.
#define DiscoveryPort  "47820"
#define TransferPort   "47821"

[Setup]
; Never change AppId: it is what lets a new version upgrade the old one in
; place instead of installing a second copy alongside it.
AppId={{8E3F1C22-5A47-4B9E-9C1D-6F2A0B7D4E13}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppContact={#AppContact}
VersionInfoVersion={#AppVersion}

DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\windows\runner\resources\app_icon.ico

OutputDir=..\dist
OutputBaseFilename={#AppName}-Setup-{#AppVersion}

; Solid LZMA2 keeps the single file as small as it can be; the Flutter runtime
; and its ICU data compress well.
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; Flutter's Windows embedder is 64-bit only.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Offer a per-user install when the user has no admin rights, so HozaSend can
; still be installed on a locked-down machine - it just skips the firewall rule.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; Shown on its own page just before Finish: how to pin, and what the firewall
; prompt is for.
InfoAfterFile=after_install.txt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; \
  Description: "Create a shortcut on my &desktop"; \
  GroupDescription: "Shortcuts:"

Name: "sendto"; \
  Description: "Add HozaSend to the right-click ''Send to'' menu"; \
  GroupDescription: "Sharing:"

Name: "shellmenu"; \
  Description: "Add ''Send with HozaSend'' to the right-click menu"; \
  GroupDescription: "Sharing:"

Name: "firewall"; \
  Description: "Allow HozaSend through Windows Firewall on private networks"; \
  GroupDescription: "Network:"; \
  Check: IsAdminInstallMode

[Files]
; The whole release folder. `recursesubdirs` is what carries data\, which holds
; the Flutter assets and the ICU data the app will not start without.
Source: "{#BuildDir}\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; \
  Comment: "Share files over your local network, with no internet"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; \
  Tasks: desktopicon
; Right-click a file, Send to, HozaSend. The oldest and least surprising way
; Windows has of saying "hand this file to that app".
Name: "{usersendto}\{#AppName}"; Filename: "{app}\{#AppExeName}"; \
  Comment: "Send this file with {#AppName}"; Tasks: sendto

[Registry]
; Puts HozaSend in the "Open with" list for every kind of file, under its own
; name rather than the exe's.
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExeName}"; \
  ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#AppName}"; \
  Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExeName}\shell\open\command"; \
  ValueType: string; ValueData: """{app}\{#AppExeName}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExeName}\SupportedTypes"; \
  ValueType: string; ValueName: "*"; ValueData: ""

; And a verb of its own on the file menu, for everyone who never goes looking
; under Send to. Windows starts one process per selected file; the app is
; single-instance and hands each one to the window already open, so a
; multi-selection arrives as a single queue rather than several windows.
Root: HKA; Subkey: "Software\Classes\*\shell\{#AppName}"; \
  ValueType: string; ValueData: "Send with {#AppName}"; \
  Flags: uninsdeletekey; Tasks: shellmenu
Root: HKA; Subkey: "Software\Classes\*\shell\{#AppName}"; \
  ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#AppExeName}"",0"; \
  Tasks: shellmenu
Root: HKA; Subkey: "Software\Classes\*\shell\{#AppName}\command"; \
  ValueType: string; ValueData: """{app}\{#AppExeName}"" ""%1"""; \
  Tasks: shellmenu

; The same on a folder, which sends everything inside it.
Root: HKA; Subkey: "Software\Classes\Directory\shell\{#AppName}"; \
  ValueType: string; ValueData: "Send with {#AppName}"; \
  Flags: uninsdeletekey; Tasks: shellmenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\{#AppName}"; \
  ValueType: string; ValueName: "Icon"; ValueData: """{app}\{#AppExeName}"",0"; \
  Tasks: shellmenu
Root: HKA; Subkey: "Software\Classes\Directory\shell\{#AppName}\command"; \
  ValueType: string; ValueData: """{app}\{#AppExeName}"" ""%1"""; \
  Tasks: shellmenu


[Run]
; Two rules, because discovery is UDP and the transfer itself is TCP. Adding
; them here is what spares the user the firewall prompt on first launch - the
; single most common reason two devices never see each other.
Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall add rule name=""{#AppName} Discovery (UDP-In)"" dir=in action=allow program=""{app}\{#AppExeName}"" protocol=UDP localport={#DiscoveryPort} profile=private"; \
  Flags: runhidden; Tasks: firewall

Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall add rule name=""{#AppName} Transfer (TCP-In)"" dir=in action=allow program=""{app}\{#AppExeName}"" protocol=TCP localport={#TransferPort} profile=private"; \
  Flags: runhidden; Tasks: firewall

Filename: "{app}\{#AppExeName}"; \
  Description: "Open {#AppName} now"; \
  Flags: nowait postinstall skipifsilent

[UninstallRun]
; Removed by name, so uninstalling does not leave permanent holes behind.
Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall delete rule name=""{#AppName} Discovery (UDP-In)"""; \
  Flags: runhidden; RunOnceId: "RemoveUdpRule"

Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall delete rule name=""{#AppName} Transfer (TCP-In)"""; \
  Flags: runhidden; RunOnceId: "RemoveTcpRule"

[UninstallDelete]
; The Flutter engine writes its cache beside the exe; without this the install
; folder survives uninstall as an empty shell.
Type: filesandordirs; Name: "{app}\data"
Type: dirifempty; Name: "{app}"
