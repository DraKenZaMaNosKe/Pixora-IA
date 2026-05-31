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

' Build command: scrcpy --serial RF8X903KZ3K
' Wrapped in `cmd /c start "" ""` so the console window is detached and
' scrcpy.exe inherits its own GUI window from SDL (the mirror window).
' Without `start`, the wscript host can suppress scrcpy's window too.
scrcpyCmd = """" & scrcpyPath & """ --serial " & deviceSerial
fullCmd = "cmd.exe /c start """" """ & scrcpyPath & """ --serial " & deviceSerial

' WindowStyle 0 hides the cmd window; scrcpy's own mirror window appears
' normally because `start` decouples it from the cmd parent.
sh.Run fullCmd, 0, False
