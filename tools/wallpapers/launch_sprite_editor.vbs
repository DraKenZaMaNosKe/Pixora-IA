' Pixora Sprite Editor — silent launcher (restart-safe)
' IMPORTANTE:
'   - "Pixora Admin" (/) y "Sprite Editor" (/sprite-editor.html) son EL MISMO servidor.
'   - Usa SOLO este launcher cuando vayas a editar sprites.
'   - Este launcher mata CUALQUIER cosa en puerto 5758 (outlier notes, instancias anteriores, etc.)
'     antes de levantar uno limpio.
'
' 1) Mata TODO en el puerto 5758
' 2) Espera a que el puerto quede libre
' 3) Lanza server fresco
' 4) Espera /api/stats
' 5) Abre /sprite-editor.html
'
' El acceso directo del escritorio ("Pixora Sprite Editor.lnk") apunta a este .vbs
' Doble click = siempre inicia limpio con el código más reciente.

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Prepend correct adb to PATH to avoid any "d:adb tools" flashes
adbDir = "C:\Users\lalo\AppData\Local\Android\Sdk\platform-tools"
Set procEnv = sh.Environment("PROCESS")
procEnv("PATH") = adbDir & ";" & procEnv("PATH")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
serverPath = scriptDir & "\wp_admin_server.py"
editorUrl  = "http://127.0.0.1:5758/sprite-editor.html"

' ─── 1) Matar TODO lo que esté usando el puerto 5758 (outlier notes, admin anterior, etc.)
' Primero matamos por nombre de proceso wp_admin_server (el nuestro)
killCmd = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
  "Get-CimInstance Win32_Process -Filter \""Name='pythonw.exe' OR Name='python.exe'\"" | " & _
  "Where-Object { $_.CommandLine -like '*wp_admin_server*' } | " & _
  "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"" "
sh.Run killCmd, 0, True

' Luego matamos CUALQUIER proceso escuchando en el puerto 5758 (para evitar choques con outlier u otros)
killPortCmd = "powershell -NoProfile -WindowStyle Hidden -Command """ & _
  "$pids = @(Get-NetTCPConnection -LocalPort 5758 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess | Sort-Object -Unique); " & _
  "foreach ($pid in $pids) { if ($pid) { Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue } }"" "
sh.Run killPortCmd, 0, True

' ─── 2) Esperar a que el puerto 5758 quede libre (máx ~5s) ───────────────────
Set probe = CreateObject("MSXML2.XMLHTTP")
freed = False
For i = 0 To 20
  WScript.Sleep 250
  On Error Resume Next
  probe.Open "GET", "http://127.0.0.1:5758/api/stats", False
  probe.Send
  ' Si el request falla (conexión rechazada) = puerto libre
  If Err.Number <> 0 Then
    freed = True
    Err.Clear
    Exit For
  End If
  Err.Clear
  On Error Goto 0
Next

' ─── 3) Resolver pythonw.exe (varias ubicaciones comunes) ─────────────────────
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

' ─── 4) Lanzar el server fresco (hidden) ─────────────────────────────────────
cmd = """" & pythonwPath & """ """ & serverPath & """"
sh.CurrentDirectory = scriptDir
sh.Run cmd, 0, False

' ─── 5) Esperar a que el server responda (máx ~6s) y abrir el editor ─────────
Set ready = CreateObject("MSXML2.XMLHTTP")
For i = 0 To 24
  WScript.Sleep 250
  On Error Resume Next
  ready.Open "GET", "http://127.0.0.1:5758/api/stats", False
  ready.Send
  If Err.Number = 0 And ready.Status >= 200 Then
    Err.Clear
    Exit For
  End If
  Err.Clear
  On Error Goto 0
Next

' Abrimos directamente el sprite editor
sh.Run editorUrl, 1, False
