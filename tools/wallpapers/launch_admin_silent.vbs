' Pixora Admin Server — silent launcher
' Inicia tools/wallpapers/wp_admin_server.py en background, sin ventana
' de consola visible. Usa pythonw.exe (Python For Windows) que descarta
' stdout/stderr a la consola pero permite que webbrowser.open abra el
' navegador con el dashboard al terminar de inicializar.
'
' Doble click al .lnk del escritorio → server arranca silencioso → tu
' navegador default abre http://localhost:5757/ con el dashboard listo.
'
' Para detener: cierra el proceso pythonw.exe desde el Administrador de
' Tareas, o reinicia la PC.

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Resolve script paths relative to this .vbs file so the shortcut works
' regardless of which directory the user double-clicks from.
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
projectDir = fso.GetParentFolderName(fso.GetParentFolderName(scriptDir))
serverPath = scriptDir & "\wp_admin_server.py"

' pythonw.exe = Python For Windows; runs without opening a console window.
' Falls back to whatever's on PATH if not in the standard install dirs.
pythonwPath = "pythonw.exe"
If fso.FileExists("C:\Python314\pythonw.exe") Then
  pythonwPath = "C:\Python314\pythonw.exe"
ElseIf fso.FileExists("C:\Python313\pythonw.exe") Then
  pythonwPath = "C:\Python313\pythonw.exe"
ElseIf fso.FileExists("C:\Python312\pythonw.exe") Then
  pythonwPath = "C:\Python312\pythonw.exe"
End If

' Run command: pythonw "wp_admin_server.py"
' Working directory = scriptDir so relative paths inside the server work.
' WindowStyle 0 = hidden, bWaitOnReturn = False so this .vbs exits immediately.
' Server writes its own log file (admin_server.log) for diagnostics — see
' wp_admin_server.py top of file for the redirection.
cmd = """" & pythonwPath & """ """ & serverPath & """"
sh.CurrentDirectory = scriptDir
sh.Run cmd, 0, False
