# Pixora Admin Server — instalador del acceso directo en el escritorio
#
# Ejecuta este script UNA vez para crear "Pixora Admin.lnk" en tu escritorio.
# El acceso directo lanza el servidor del dashboard de forma silenciosa
# (sin ventana de consola) y abre tu navegador con http://localhost:5757/.
#
# Uso:
#   1. Abre PowerShell en esta carpeta
#   2. Si es la primera vez:  Set-ExecutionPolicy -Scope Process Bypass
#   3. Ejecuta:  .\install_admin_shortcut.ps1
#
# Después solo necesitas doble click al icono "Pixora Admin" del escritorio.

$ErrorActionPreference = "Stop"

# Resolve absolute paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$vbsPath   = Join-Path $scriptDir "launch_admin_silent.vbs"
$desktop   = [Environment]::GetFolderPath('Desktop')
$shortcut  = Join-Path $desktop "Pixora Admin.lnk"

if (-not (Test-Path $vbsPath)) {
    Write-Host "ERROR: launch_admin_silent.vbs no existe en:" -ForegroundColor Red
    Write-Host "  $vbsPath" -ForegroundColor Red
    exit 1
}

# Optional icon — fallback to default if no icon file is shipped with the project
$iconPath = Join-Path $scriptDir "..\..\assets\icon_p.png"
$iconResolved = ""
if (Test-Path $iconPath) {
    # Windows shortcuts only accept .ico / .exe / .dll for icons; PNG won't work
    # directly. Use the wscript.exe icon as a clean default — looks like a small
    # gear / script which fits a "launcher" intent.
    $iconResolved = "wscript.exe, 0"
}

# Build the .lnk via WScript.Shell COM object
$wshell = New-Object -ComObject WScript.Shell
$lnk = $wshell.CreateShortcut($shortcut)
$lnk.TargetPath       = "wscript.exe"
$lnk.Arguments        = "`"$vbsPath`""
$lnk.WorkingDirectory = $scriptDir
$lnk.WindowStyle      = 7  # 7 = minimized (no flash); 0 = hidden via vbs anyway
$lnk.Description      = "Pixora Admin Dashboard - lanza el servidor en silencio y abre el navegador"
if ($iconResolved -ne "") {
    $lnk.IconLocation = $iconResolved
}
$lnk.Save()

Write-Host ""
Write-Host "OK Acceso directo creado:" -ForegroundColor Green
Write-Host "   $shortcut" -ForegroundColor White
Write-Host ""
Write-Host "Doble click al icono 'Pixora Admin' del escritorio para lanzar el dashboard." -ForegroundColor Cyan
Write-Host "El servidor arranca silencioso y tu navegador abrira http://localhost:5757/" -ForegroundColor Cyan
Write-Host ""
