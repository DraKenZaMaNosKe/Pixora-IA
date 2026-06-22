' Pixora Admin Server — silent launcher (restart-safe v2)
' 1) Mata SOLO los pythons que estén corriendo wp_admin_server.py
'    (vía PowerShell Stop-Process filtrando por CommandLine — método
'    más confiable que WMI Terminate desde VBS).
' 2) Espera a que el puerto 5757 quede libre (poll, no sleep ciego).
' 3) Lanza una instancia fresca, oculta.
' 4) Abre el dashboard en el navegador.
'
' Doble click al .lnk del escritorio → siempre arranca limpio, sin
' tocar otros pythons que tengas corriendo (notebooks, scripts, etc).

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
serverPath = scriptDir & "\wp_admin_server.py"

' ─── 1) Kill cualquier wp_admin_server.py previo ────────────────────────────
' Usamos PowerShell con WindowStyle Hidden — más rápido y robusto que el
' enfoque WMI puro de VBS (que requiere privilegios específicos para
' Terminate y falla silencioso en algunas máquinas).
killCmd = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
  "Get-CimInstance Win32_Process -Filter \""Name='pythonw.exe' OR Name='python.exe'\"" | " & _
  "Where-Object { $_.CommandLine -like '*wp_admin_server*' } | " & _
  "ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }"" "
sh.Run killCmd, 0, True   ' bWaitOnReturn=True — esperar a que termine de matar

' ─── 2) Esperar a que puerto 5757 se libere (max 5s) ────────────────────────
Set httpProbe = CreateObject("MSXML2.XMLHTTP")
freed = False
For i = 0 To 20
  WScript.Sleep 250
  On Error Resume Next
  httpProbe.Open "GET", "http://127.0.0.1:5757/api/stats", False
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
  httpReady.Open "GET", "http://127.0.0.1:5757/api/stats", False
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
sh.Run "http://127.0.0.1:5757/", 1, False
