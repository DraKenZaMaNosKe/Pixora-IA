' Pixora — silent scrcpy launcher for the Samsung device.
' Doble click al .lnk del escritorio → scrcpy arranca y abre la ventana
' espejo del Samsung sin que aparezca consola negra de fondo.
'
' Para detener: cierra la ventana de scrcpy (X) o el proceso scrcpy.exe
' desde el Administrador de Tareas.

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Samsung device serial (adb devices). If you change phones, update this.
deviceSerial = "RF8X903KZ3K"

' Search scrcpy.exe in common locations. Winget installs land under a
' versioned subfolder (e.g. scrcpy-win64-v4.0\) so we iterate the package
' dir to stay future-proof when scrcpy updates.
scrcpyPath = "scrcpy.exe"  ' fallback: PATH lookup
localAppData = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%")
candidates = Array( _
  "C:\scrcpy\scrcpy.exe", _
  "C:\Program Files\scrcpy\scrcpy.exe", _
  "C:\Program Files (x86)\scrcpy\scrcpy.exe", _
  "D:\scrcpy\scrcpy.exe", _
  "D:\Tools\scrcpy\scrcpy.exe", _
  localAppData & "\Microsoft\WindowsApps\scrcpy.exe", _
  localAppData & "\scoop\apps\scrcpy\current\scrcpy.exe" _
)
For Each c In candidates
  If fso.FileExists(c) Then
    scrcpyPath = c
    Exit For
  End If
Next

' Winget package — version-suffixed subfolder, walk it.
wingetDir = localAppData & "\Microsoft\WinGet\Packages\Genymobile.scrcpy_Microsoft.Winget.Source_8wekyb3d8bbwe"
If scrcpyPath = "scrcpy.exe" And fso.FolderExists(wingetDir) Then
  Set wgFolder = fso.GetFolder(wingetDir)
  For Each subDir In wgFolder.SubFolders
    candidate = subDir.Path & "\scrcpy.exe"
    If fso.FileExists(candidate) Then
      scrcpyPath = candidate
      Exit For
    End If
  Next
End If

' --- Buscar adb.exe (para pre-iniciar el server sin ventana) ---
adbPath = "adb.exe"
adbCandidates = Array( _
  "C:\Users\lalo\AppData\Local\Android\Sdk\platform-tools\adb.exe", _
  localAppData & "\Android\Sdk\platform-tools\adb.exe", _
  "C:\Program Files (x86)\Android\android-sdk\platform-tools\adb.exe" _
)
For Each c In adbCandidates
  If fso.FileExists(c) Then
    adbPath = c
    Exit For
  End If
Next
If adbPath = "adb.exe" Then
  On Error Resume Next
  adbPath = sh.RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\adb.exe\")
  On Error Goto 0
End If

' Prepend adb dir to PATH so any child (scrcpy, adb inside) uses the lalo one, not D:\adb
adbDir = fso.GetParentFolderName(adbPath)
Set procEnv = sh.Environment("PROCESS")
procEnv("PATH") = adbDir & ";" & procEnv("PATH")

' --- Pre-iniciar "adb start-server" completamente oculto ---
' Esto evita que aparezca la ventanita negra de "adb" cuando scrcpy conecta.
psAdb = "powershell.exe -NoProfile -WindowStyle Hidden -Command "" " & _
  "$si = New-Object System.Diagnostics.ProcessStartInfo; " & _
  "$si.FileName = '" & adbPath & "'; " & _
  "$si.Arguments = 'start-server'; " & _
  "$si.CreateNoWindow = $true; " & _
  "$si.UseShellExecute = $false; " & _
  "$si.RedirectStandardOutput = $true; " & _
  "$si.RedirectStandardError = $true; " & _
  "[void][System.Diagnostics.Process]::Start($si) """
sh.Run psAdb, 0, True
WScript.Sleep 600

' Build command: scrcpy --serial RF8X903KZ3K
' Wrapped in `cmd /c start "" ""` so the console window is detached and
' scrcpy.exe inherits its own GUI window from SDL (the mirror window).
' Without `start`, the wscript host can suppress scrcpy's window too.
fullCmd = "cmd.exe /c start """" """ & scrcpyPath & """ --serial " & deviceSerial

' WindowStyle 0 hides the cmd window; scrcpy's own mirror window appears
' normally because `start` decouples it from the cmd parent.
sh.Run fullCmd, 0, False

