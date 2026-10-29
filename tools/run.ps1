param(
    [string]$Godot,
    [ValidateSet('menu', 'solo', 'host', 'join')][string]$Mode = 'menu',
    [string]$Address = '127.0.0.1',
    [ValidateRange(1024, 65535)][int]$Port = 24570,
    [string]$SaveDir,
    [switch]$Editor
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$taskEngine = Find-MistboundGodot $Godot
$taskProject = Split-Path $PSScriptRoot -Parent
$taskArgs = @('--path', $taskProject)
if ($Editor) { $taskArgs += '--editor' }
elseif ($Mode -ne 'menu') {
    $taskArgs += '--'
    $taskArgs += if ($Mode -eq 'join') { '--join=' + $Address } else { '--' + $Mode }
    $taskArgs += '--port=' + $Port
}
$taskPreviousSaveDir = $env:MISTBOUND_SAVE_DIR
try {
    if ($SaveDir) { $env:MISTBOUND_SAVE_DIR = [IO.Path]::GetFullPath($SaveDir) }
    Write-Output "Project: $taskProject"
    Write-Output "Godot: $taskEngine"
    & $taskEngine @taskArgs
}
finally { $env:MISTBOUND_SAVE_DIR = $taskPreviousSaveDir }
