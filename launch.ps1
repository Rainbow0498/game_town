param([string]$GodotPath = "", [string]$PythonPath = "")
$ErrorActionPreference = 'Stop'
if (-not $GodotPath) {
    $candidate = Get-Command godot,godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidate) { $GodotPath = $candidate.Source }
}
if (-not $GodotPath -and (Test-Path -LiteralPath 'D:\Godot')) {
    $candidate = Get-ChildItem -LiteralPath 'D:\Godot' -Filter 'Godot_v4*_win64.exe' -File | Sort-Object Name -Descending | Select-Object -First 1
    if ($candidate) { $GodotPath = $candidate.FullName }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot 4 was not found. Run launch.ps1 -GodotPath "C:\path\to\Godot.exe", or open project.godot in Godot.'
}
# Import first so a fresh checkout works without opening the editor manually.
if ($PythonPath) { $env:TOWN_PYTHON = $PythonPath }
& $GodotPath --headless --path $PSScriptRoot --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot asset import failed.' }
Start-Process -FilePath $GodotPath -ArgumentList @('--path', ('"' + $PSScriptRoot + '"')) -WorkingDirectory $PSScriptRoot
