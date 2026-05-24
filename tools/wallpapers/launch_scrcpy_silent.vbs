' Silent launcher para scrcpy con args configurados para el Samsung de Pixora.
' Doble click al .lnk del escritorio → scrcpy arranca sin ventana de cmd visible.
' La ventana de scrcpy SÍ se ve (tiene barra de título y se puede mover/redimensionar).

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Path resolution — buscar scrcpy en la ruta de winget user-scope.
scrcpyPath = ""
localAppData = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%")
wingetBase = localAppData & "\Microsoft\WinGet\Packages\Genymobile.scrcpy_Microsoft.Winget.Source_8wekyb3d8bbwe"

' Buscar la subcarpeta scrcpy-win64-vX.Y (la versión cambia con cada update)
If fso.FolderExists(wingetBase) Then
  For Each f In fso.GetFolder(wingetBase).SubFolders
    If InStr(LCase(f.Name), "scrcpy-win") > 0 Then
      candidate = f.Path & "\scrcpy.exe"
      If fso.FileExists(candidate) Then
        scrcpyPath = candidate
        Exit For
      End If
    End If
  Next
End If

' Fallback: scrcpy en PATH (si fue instalado de otra forma)
If scrcpyPath = "" Then scrcpyPath = "scrcpy.exe"

' Args: device serial + title + fps cap. SIN --window-borderless para que la
' ventana tenga barra de título y se pueda mover y redimensionar normalmente.
args = "-s RF8X903KZ3K --window-title=""Samsung A15 (Pixora)"" --max-fps=30"

' WindowStyle 0 = oculta la ventana del proceso lanzador (el cmd intermedio).
' scrcpy abre su propia ventana de mirror, esa SÍ se ve.
' bWaitOnReturn = False para que este .vbs salga inmediatamente.
sh.Run """" & scrcpyPath & """ " & args, 0, False
