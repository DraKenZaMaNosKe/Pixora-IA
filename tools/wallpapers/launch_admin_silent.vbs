' Pixora Admin Server — silent launcher (restart-safe v2)
' 1) Mata SOLO los pythons que estén corriendo wp_admin_server.py
'    (vía PowerShell Stop-Process filtrando por CommandLine — método
'    más confiable que WMI Terminate desde VBS).
' 2) Espera a que el puerto 5758 quede libre (poll, no sleep ciego).
' 3) Lanza una instancia fresca, oculta.
' 4) Abre el dashboard en el navegador.
'
' Doble click al .lnk del escritorio → siempre arranca limpio, sin
' tocar otros pythons que tengas corriendo (notebooks, scripts, etc).

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Prepend correct adb to PATH to avoid any "d:adb tools" flashes
adbDir = "C:\Users\lalo\AppData\Local\Android\Sdk\platform-tools"
Set procEnv = sh.Environment("PROCESS")
procEnv("PATH") = adbDir & ";" & procEnv("PATH")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
serverPath = scriptDir & "\wp_admin_server.py"

' ─── 1) Mata TODO lo que use el puerto 5758 (wp_admin + outlier notes + cualquier otro)
' Primero los wp_admin_server
killCmd = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
  "Get-CimInstance Win32_Process -Filter \""Name='pythonw.exe' OR Name='python.exe'\"" | " & _
  "Where-Object { $_.CommandLine -like '*wp_admin_server*' } | " & _
  "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"" "
sh.Run killCmd, 0, True

' Luego cualquier listener en 5758 (outlier, etc.)
killPortCmd = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
  "$pids = @(Get-NetTCPConnection -LocalPort 5758 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess | Sort-Object -Unique); " & _
  "foreach ($pid in $pids) { if ($pid) { Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue } }"" "
sh.Run killPortCmd, 0, True

' ─── 2) Esperar a que puerto 5758 se libere (max 5s) ────────────────────────
Set httpProbe = CreateObject("MSXML2.XMLHTTP")
freed = False
For i = 0 To 20
  WScript.Sleep 250
  On Error Resume Next
  httpProbe.Open "GET", "http://127.0.0.1:5758/api/stats", False
  httpProbe.Send
  ' Si el GET falla con conexión rechazada → puerto libre.
  ' Si responde algo → todavía vive algo, seguir esperando.
  If Err.Number <> 0 Then
    freed = True
    Err.Clear
    Exit For
  End If
  On Error Goto 0
Next

' ─── 3) Resolver pythonw.exe ────────────────────────────────────────────────
pythonwPath = "pythonw.exe"
localAppData = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%")
If fso.FileExists("C:\Python314\pythonw.exe") Then
  pythonwPath = "C:\Python314\pythonw.exe"
ElseIf fso.FileExists("C:\Python313\pythonw.exe") Then
  pythonwPath = "C:\Python313\pythonw.exe"
ElseIf fso.FileExists("C:\Python312\pythonw.exe") Then
  pythonwPath = "C:\Python312\pythonw.exe"
ElseIf fso.FileExists(localAppData & "\Programs\Python\Python314\pythonw.exe") Then
  pythonwPath = localAppData & "\Programs\Python\Python314\pythonw.exe"
ElseIf fso.FileExists(localAppData & "\Programs\Python\Python313\pythonw.exe") Then
  pythonwPath = localAppData & "\Programs\Python\Python313\pythonw.exe"
ElseIf fso.FileExists(localAppData & "\Programs\Python\Python312\pythonw.exe") Then
  pythonwPath = localAppData & "\Programs\Python\Python312\pythonw.exe"
End If

' ─── 4) Lanzar el server (hidden, sin esperar) ──────────────────────────────
cmd = """" & pythonwPath & """ """ & serverPath & """"
sh.CurrentDirectory = scriptDir
sh.Run cmd, 0, False

' ─── 5) Esperar a que /api/stats responda (max 6s), luego abrir browser ─────
Set httpReady = CreateObject("MSXML2.XMLHTTP")
ready = False
For i = 0 To 24
  WScript.Sleep 250
  On Error Resume Next
  httpReady.Open "GET", "http://127.0.0.1:5758/api/stats", False
  httpReady.Send
  If Err.Number = 0 And httpReady.Status >= 200 Then
    ready = True
    Err.Clear
    Exit For
  End If
  Err.Clear
  On Error Goto 0
Next

' Abre dashboard incluso si el ready-check no respondió (puede tardar más).
sh.Run "http://127.0.0.1:5758/", 1, False
