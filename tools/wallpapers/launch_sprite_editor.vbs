' Pixora Sprite Editor — silent launcher
' 1) If admin server is already running on 5757, just opens the editor URL.
' 2) If not, launches the admin server first (re-uses launch_admin_silent.vbs
'    logic), waits until /api/stats responds, then opens the editor.
' Doble click al .lnk del escritorio -> editor listo en segundos.

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
serverPath = scriptDir & "\wp_admin_server.py"
editorUrl  = "http://127.0.0.1:5757/sprite-editor.html"

' --- 1) Probe if the server is already running -----------------------------
Set probe = CreateObject("MSXML2.XMLHTTP")
alive = False
On Error Resume Next
probe.Open "GET", "http://127.0.0.1:5757/api/stats", False
probe.Send
If Err.Number = 0 And probe.Status >= 200 Then alive = True
Err.Clear
On Error Goto 0

' --- 2) If not alive, launch the server (hidden) ---------------------------
If Not alive Then
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
  cmd = """" & pythonwPath & """ """ & serverPath & """"
  sh.CurrentDirectory = scriptDir
  sh.Run cmd, 0, False

  ' Poll until /api/stats responds (max 20s — Python imports can be slow on cold start)
  Set ready = CreateObject("MSXML2.XMLHTTP")
  For i = 0 To 80
    WScript.Sleep 250
    On Error Resume Next
    ready.Open "GET", "http://127.0.0.1:5757/api/stats", False
    ready.Send
    If Err.Number = 0 And ready.Status >= 200 Then
      Err.Clear
      Exit For
    End If
    Err.Clear
    On Error Goto 0
  Next
  ' Extra 400ms grace so first browser fetch doesn't race the server's last warm-up
  WScript.Sleep 400
End If

' --- 3) Open the editor in the default browser -----------------------------
sh.Run editorUrl, 1, False
