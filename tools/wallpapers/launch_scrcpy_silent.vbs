' Pixora — silent scrcpy launcher for ANY connected device.
' Doble click al .lnk del escritorio → scrcpy arranca una ventana por cada
' device conectado (Samsung y/o Huawei). Sin consola negra de fondo.
'
' Devices conocidos:
'   RF8X903KZ3K       → Samsung A155M (1080x2340) — referencia principal
'   G2R4C17516000149  → Huawei (1080x1920) — secondary, para validar cross-device
'
' Si conectas un device nuevo, agrégalo al array DEVICES más abajo con su
' label (aparece en el título de la ventana scrcpy).
'
' Para detener: cierra la ventana de scrcpy (X) o el proceso scrcpy.exe
' desde el Administrador de Tareas.

Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' --- Devices conocidos: serial → window title → extra flags -----------
' Format: serial|label|extraFlags. La VBS recorre adb devices y solo lanza
' scrcpy para serials que estén actualmente "device" (no offline /
' unauthorized).
'
' extraFlags: flags scrcpy específicos del device. Huawei (Android 7.0)
' necesita --no-audio (audio no soportado < Android 11) y
' --video-codec=h264 (h265 falla en encoders viejos), si no scrcpy tira
' "Server connection failed".
DEVICES = Array( _
  "RF8X903KZ3K|Samsung A155M (1080x2340)|", _
  "G2R4C17516000149|Huawei (1080x1920)|--no-audio --video-codec=h264 --max-fps=30" _
)

' --- Localizar scrcpy.exe (mismas rutas que antes) --------------------
scrcpyPath  = "scrcpy.exe"
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

' --- Localizar adb.exe ------------------------------------------------
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

' Prepend adb dir to PATH so scrcpy uses the same adb we found.
adbDir = fso.GetParentFolderName(adbPath)
Set procEnv = sh.Environment("PROCESS")
procEnv("PATH") = adbDir & ";" & procEnv("PATH")

' --- Pre-iniciar "adb start-server" oculto ----------------------------
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

' --- Pedir adb devices (parseable) ------------------------------------
' Usamos un archivo temporal porque WScript.Exec dispara una ventana de
' consola que el usuario quiere evitar. PowerShell con -WindowStyle Hidden
' redirige stdout al archivo sin ventana visible.
tmpFile = fso.GetSpecialFolder(2).Path & "\pixora_adb_devices.txt"
psList = "powershell.exe -NoProfile -WindowStyle Hidden -Command "" " & _
  "& '" & adbPath & "' devices | Out-File -Encoding ascii '" & tmpFile & "' """
sh.Run psList, 0, True
WScript.Sleep 400

connectedSerials = ""
If fso.FileExists(tmpFile) Then
  Set ts = fso.OpenTextFile(tmpFile, 1)
  raw = ts.ReadAll
  ts.Close
  fso.DeleteFile tmpFile, True
  ' Each line after the header: "<serial>\t<state>". We want lines where
  ' state == "device" (not "offline" / "unauthorized" / empty).
  lines = Split(raw, vbCrLf)
  For Each ln In lines
    parts = Split(ln, vbTab)
    If UBound(parts) >= 1 Then
      If Trim(parts(1)) = "device" Then
        connectedSerials = connectedSerials & "|" & Trim(parts(0)) & "|"
      End If
    End If
  Next
End If

' --- Por cada device conocido, si está conectado lanza scrcpy ---------
launched = 0
For Each entry In DEVICES
  pair = Split(entry, "|")
  serial = pair(0)
  label  = pair(1)
  If InStr(connectedSerials, "|" & serial & "|") > 0 Then
    ' Wrap in `cmd /c start "" ""` so scrcpy's window is decoupled from
    ' the wscript host and not suppressed.
    fullCmd = "cmd.exe /c start """" """ & scrcpyPath & """ " & _
              "--serial " & serial & " " & _
              "--window-title=""" & label & """"
    sh.Run fullCmd, 0, False
    launched = launched + 1
    WScript.Sleep 350  ' tiny gap so two scrcpy startups don't race on adb
  End If
Next

' --- Friendly hint si NO había ningún device conocido conectado -------
If launched = 0 Then
  MsgBox "No hay ningun device conocido conectado." & vbCrLf & vbCrLf & _
    "Conecta el Samsung (RF8X903KZ3K) o el Huawei (G2R4C17516000149) " & _
    "via USB con depuracion activada y vuelve a intentar.", _
    vbInformation, "Pixora · scrcpy"
End If
